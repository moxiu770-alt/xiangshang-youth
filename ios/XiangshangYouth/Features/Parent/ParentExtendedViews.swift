import SwiftUI
import UIKit
import AVKit
import PhotosUI
import UniformTypeIdentifiers

struct ParentCourseTeaser: View {
    let image: String; let title: String
    @State private var isPresented = false
    var body: some View { Button { isPresented = true } label: { VStack(alignment: .leading, spacing: 5) { Image(image).resizable().scaledToFill().frame(height: 52).frame(maxWidth: .infinity).clipped(); Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(2); Text("免费学习 ›").font(.system(size: 12)).foregroundStyle(ReferenceColor.green) }.padding(6).background(.white, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).sheet(isPresented: $isPresented) { CourseDetailSheet(title: title) } }
}

struct ParentArticleRow: View {
    let title: String; let detail: String
    @State private var isPresented = false
    var body: some View { Button { isPresented = true } label: { HStack { Image(systemName: "book.closed.fill").foregroundStyle(ReferenceColor.green).frame(width: 34, height: 34).background(ReferenceColor.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .bold)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).sheet(isPresented: $isPresented) { HealthArticleSheet(title: title) } }
}

/// The two missing parent tabs from the supplied information architecture.
/// All cards are actionable and can switch to the remote source without changing the route contract.
private struct LocalCourseCard: Identifiable {
    let id: String
    let icon: String
    let title: String
    let color: Color
}

struct ParentCoursesDashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedKind = 0
    @State private var selectedCourse: LocalCourseCard?
    @State private var selectedRemoteCourse: RemoteLesson?
    @State private var catalogShown = false
    @State private var loadedCourseChildID: String?
    @State private var recommendationMessage: String?
    private let publicCourses = [
        LocalCourseCard(id: "local:public-fitness", icon: "figure.run", title: "体质成长课", color: ReferenceColor.blue),
        LocalCourseCard(id: "local:public-vision", icon: "eye.fill", title: "视力守护课", color: ReferenceColor.green),
        LocalCourseCard(id: "local:public-oral", icon: "mouth.fill", title: "口腔健康课", color: ReferenceColor.purple),
        LocalCourseCard(id: "local:public-wellbeing", icon: "brain.head.profile", title: "心理舒展课", color: ReferenceColor.pink)
    ]
    private let schoolCourses = [
        LocalCourseCard(id: "local:school-fitness", icon: "figure.run", title: "校内体能提升课", color: ReferenceColor.blue),
        LocalCourseCard(id: "local:school-vision", icon: "eye.fill", title: "校园视力守护课", color: ReferenceColor.green),
        LocalCourseCard(id: "local:school-after-class", icon: "figure.strengthtraining.traditional", title: "课后运动巩固课", color: ReferenceColor.purple),
        LocalCourseCard(id: "local:school-family", icon: "person.3.fill", title: "亲子运动指导课", color: ReferenceColor.pink)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我的课程", showsBell: false)
                ReferenceHeader(name: state.selectedChild?.name ?? "未选择孩子", school: "\(state.selectedChild?.className ?? "尚未绑定班级") · 成长课程", initial: String((state.selectedChild?.name ?? "孩").prefix(1)), avatarAsset: "ChildAvatar")
                Picker("课程类型", selection: $selectedKind) { Text("公益课程").tag(0); Text("学校课程").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal, 12)
                ReferenceSectionTitle(title: selectedKind == 0 ? "公益课堂" : "精选学校课程", trailing: "全部课程", action: { catalogShown = true }).padding(.horizontal, 12)
                if state.usesRemoteDataSource {
                    if state.coursesLoading { LoadingStateView() }
                    else if let error = state.coursesError { ErrorStateView(message: error) { if let child = state.selectedChild { Task { await state.loadCourses(for: child) } } } }
                    else if state.remoteCourses.isEmpty { EmptyStateView(title: "暂无已分配课程", detail: "学校或平台分配课程后会显示在这里。") }
                    else { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { ForEach(state.remoteCourses.filter { selectedKind == 0 ? $0.videoSource != nil : true }, id: \.lessonID) { course in
                        Button { selectedRemoteCourse = course } label: { VStack(alignment: .leading, spacing: 7) { Image(systemName: "play.circle.fill").font(.system(size: 23, weight: .semibold)).foregroundStyle(ReferenceColor.blue); Text(course.title).font(.system(size: 13, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(2); Text(course.completed ? "已完成" : course.lastPositionMs > 0 ? "继续学习" : "开始学习").font(.system(size: 12)).foregroundStyle(ReferenceColor.green) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(ReferenceColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11)) }.buttonStyle(.plain) } }.padding(.horizontal, 12) }
                } else { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(selectedKind == 0 ? publicCourses : schoolCourses) { course in
                        Button { selectedCourse = course } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Image(systemName: course.icon).font(.system(size: 23, weight: .semibold)).foregroundStyle(course.color)
                                Text(course.title).font(.system(size: 13, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(2)
                                Text(selectedKind == 0 ? "公益 · 立即学习" : "校内课程 · 查看课程").font(.system(size: 12)).foregroundStyle(course.color)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(course.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12) }
                Button { selectedCourse = LocalCourseCard(id: "support:course", icon: "message.fill", title: "客服咨询", color: ReferenceColor.blue) } label: {
                    HStack { Image(systemName: "message.fill"); VStack(alignment: .leading) { Text("课程咨询").font(.system(size: 12, weight: .bold)); Text("填写后自动保存并同步").font(.system(size: 12)) }; Spacer(); Image(systemName: "chevron.right") }
                        .foregroundStyle(ReferenceColor.blue).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.horizontal, 12)
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .task {
            if state.usesRemoteDataSource { await state.loadClassPosts() }
        }
        .overlay {
            if let error = state.error, state.data == nil { ErrorStateView(message: error) { Task { await state.refreshDashboard() } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ReferenceColor.canvas) }
            else if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
            else if state.selectedChild == nil { ParentBindingPrompt() }
        }
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(title: course.title, courseID: course.id, lessonID: "lesson:\(course.id)")
        }
        .sheet(item: $selectedRemoteCourse) { course in CourseDetailSheet(title: course.title, courseID: course.courseID, lessonID: course.lessonID, remoteVideoSource: course.videoSource, initialPositionMs: course.lastPositionMs, expectedProgressVersion: course.version) }
        .sheet(isPresented: $catalogShown) {
            CourseCatalogSheet(kind: selectedKind == 0 ? "公益课堂" : "精选学校课程", isSchoolCourse: selectedKind == 1)
        }
        .alert("暂无法打开课程", isPresented: Binding(get: { recommendationMessage != nil }, set: { if !$0 { recommendationMessage = nil } })) {
            Button("知道了") { recommendationMessage = nil }
        } message: { Text(recommendationMessage ?? "") }
        .task(id: state.selectedChild?.id) {
            guard let child = state.selectedChild else { return }
            loadedCourseChildID = nil
            if state.usesRemoteDataSource { await state.loadCourses(for: child) }
            loadedCourseChildID = child.id
            resolveRecommendedCourseIfReady()
        }
        .onChange(of: state.remoteCourses.map(\.lessonID)) { _, _ in resolveRecommendedCourseIfReady() }
        .onChange(of: state.courseRecommendationTarget) { _, _ in resolveRecommendedCourseIfReady() }
    }

    private func resolveRecommendedCourseIfReady() {
        guard let target = state.courseRecommendationTarget,
              let child = state.selectedChild,
              target.childID == child.id,
              loadedCourseChildID == child.id else { return }
        if !state.usesRemoteDataSource {
            guard let stableID = target.courseID ?? target.lessonID else {
                recommendationMessage = "该课程建议缺少稳定课程编号，请刷新报告后再试。"
                state.clearRecommendedCourseTarget()
                return
            }
            selectedCourse = LocalCourseCard(id: stableID, icon: "play.circle.fill", title: target.title, color: ReferenceColor.blue)
            state.clearRecommendedCourseTarget()
            return
        }
        guard state.remoteCoursesChildID == child.id, !state.coursesLoading else { return }
        guard let courseID = target.courseID, let lessonID = target.lessonID else {
            recommendationMessage = "该报告的课程建议尚未包含可播放课程信息，请在学校同步课程后再试。"
            state.clearRecommendedCourseTarget()
            return
        }
        if let lesson = state.remoteCourses.first(where: { $0.courseID == courseID && $0.lessonID == lessonID }) {
            selectedRemoteCourse = lesson
        } else if state.coursesError == nil {
            recommendationMessage = "学校暂未为该孩子分配这节推荐课程。"
        }
        if state.coursesError == nil { state.clearRecommendedCourseTarget() }
    }
}

private struct CourseCatalogSheet: View {
    let kind: String
    let isSchoolCourse: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCourse: LocalCourseCard?
    private var courses: [LocalCourseCard] {
        isSchoolCourse
            ? [LocalCourseCard(id: "local:school-fitness", icon: "figure.run", title: "校内体能提升课", color: ReferenceColor.blue), LocalCourseCard(id: "local:school-vision", icon: "eye.fill", title: "校园视力守护课", color: ReferenceColor.green), LocalCourseCard(id: "local:school-after-class", icon: "figure.strengthtraining.traditional", title: "课后运动巩固课", color: ReferenceColor.purple), LocalCourseCard(id: "local:school-family", icon: "person.3.fill", title: "亲子运动指导课", color: ReferenceColor.pink)]
            : [LocalCourseCard(id: "local:public-fitness", icon: "figure.run", title: "体质成长课", color: ReferenceColor.blue), LocalCourseCard(id: "local:public-vision", icon: "eye.fill", title: "视力守护课", color: ReferenceColor.green), LocalCourseCard(id: "local:public-oral", icon: "mouth.fill", title: "口腔健康课", color: ReferenceColor.purple), LocalCourseCard(id: "local:public-wellbeing", icon: "brain.head.profile", title: "心理舒展课", color: ReferenceColor.pink)]
    }

    var body: some View {
        NavigationStack {
            List {
                Section(kind) {
                    ForEach(courses) { course in
                        Button { selectedCourse = course } label: {
                            Label(course.title, systemImage: course.icon)
                                .foregroundStyle(ReferenceColor.navy)
                        }
                    }
                }
            }
            .navigationTitle("课程目录")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(item: $selectedCourse) { course in
                CourseDetailSheet(title: course.title, courseID: course.id, lessonID: "lesson:\(course.id)")
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
    private let pinnedNoticeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private var classMemberCount: Int {
        guard let classID = state.selectedChild?.classID else { return 0 }
        return state.data?.students.filter { $0.classID == classID }.count ?? 0
    }
    // A family feed needs the class size, not other children's identities.
    // Keep the roster private unless the school later provides explicit consent.
    private var visibleClassmates: [Student] { [] }
    private var currentMonthCheckInCount: Int {
        state.localFeatures.checkInDates.filter { $0.hasPrefix(Self.monthKeyFormatter.string(from: .now)) }.count
    }
    private var currentParentName: String { state.activeDisplayName }
    private var classTeacherName: String {
        guard let classID = state.selectedChild?.classID else { return "班级教师" }
        return state.data?.classes.first(where: { $0.id == classID })?.teacherName ?? "班级教师"
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                circleHeader
                postsFeed
                classInteractionSection
                checkInSection
                courseSections
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil { ErrorStateView(message: error) { Task { await state.refreshDashboard() } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ReferenceColor.canvas) }
            else if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
            else if state.selectedChild == nil { ParentBindingPrompt() }
        }
        .sheet(isPresented: $isComposerShown) { PublishClassPostSheet(author: currentParentName) }
        .sheet(item: $editingPost) { post in PublishClassPostSheet(author: post.author, editingPost: post) }
        .sheet(item: Binding(get: { selectedMoment.map(CourseSheetItem.init) }, set: { selectedMoment = $0?.name })) { item in
            if item.name.contains("互动") || item.name.contains("打卡记录") || item.name.contains("评论") {
                CircleInfoSheet(title: item.name)
            } else {
                CourseDetailSheet(title: item.name)
            }
        }
        .sheet(item: Binding(get: { commentPostID.map(CommentSheetItem.init) }, set: { commentPostID = $0?.id })) { item in
            NavigationStack { VStack(spacing: 14) { if commentSubmitted { Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(ReferenceColor.green); Text("评论已保存").font(.headline); Text(state.usesRemoteDataSource ? "评论已提交到班级圈，审核状态以学校服务为准。" : "评论已保存，联网后自动同步到班级圈。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center); Button("完成") { commentPostID = nil }.buttonStyle(.borderedProminent) } else { Text("给这条动态留言").font(.headline); TextField("说点鼓励的话…", text: $commentDraft, axis: .vertical).textFieldStyle(.roundedBorder); Button("保存评论") { if let postID = commentPostID { state.addClassPostComment(postID: postID, text: commentDraft); state.clearDraft(commentDraftKey(for: postID)) }; commentSubmitted = true }.buttonStyle(.borderedProminent).disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }; Spacer() }.padding(20).navigationTitle("评论").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { commentPostID = nil } } } }
        }
        .onChange(of: commentDraft) { _, value in
            guard let postID = commentPostID, !commentSubmitted else { return }
            state.saveDraft(value, key: commentDraftKey(for: postID))
        }
    }
    private func commentDraftKey(for postID: UUID) -> String { "class-comment-\(postID.uuidString)" }
    private func openComment(for postID: UUID) {
        commentSubmitted = false
        commentDraft = state.localFeatures.drafts[commentDraftKey(for: postID)] ?? ""
        commentPostID = postID
    }
    @ViewBuilder private var circleHeader: some View {
        ParentPageNavigation(title: "班级圈", showsBell: false)
        ReferenceHeader(
            name: state.selectedChild?.name ?? "未选择孩子",
            school: "\(state.selectedChild?.className ?? "尚未绑定班级") · \(classMemberCount)人",
            initial: String((state.selectedChild?.name ?? "孩").prefix(1)),
            avatarAsset: "ChildAvatar"
        )
        ReferenceCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本班家校圈").font(.system(size: 16, weight: .bold))
                    Text("分享运动成长，和老师保持联系").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(classMemberCount)").font(.system(size: 20, weight: .bold)).foregroundStyle(ReferenceColor.blue)
                    Text("班级成员").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        HStack(spacing: 8) {
            ForEach(["全部", "老师动态", "家长分享"], id: \.self) { filter in
                Button { selectedFilter = filter } label: {
                    Text(filter)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedFilter == filter ? Color.white : ReferenceColor.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedFilter == filter ? ReferenceColor.blue : ReferenceColor.sky, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        Button { isComposerShown = true } label: {
            Label("发布班级动态", systemImage: "square.and.pencil")
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
    private var classInteractionSection: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 8) {
                ReferenceSectionTitle(title: "本班互动", trailing: "查看说明", action: { selectedMoment = "班级互动说明" })
                if visibleClassmates.isEmpty {
                    Text("暂无本班可见名单，学校完成分班后会显示在这里。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    HStack { ForEach(visibleClassmates) { student in classmate(student) } }
                    Text("本页不展示或生成班级评优、排名；学校正式表彰以班主任通知为准。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
    }
    private var checkInSection: some View {
        let hasCheckIns = currentMonthCheckInCount > 0
        let title = hasCheckIns ? "本月已保存 \(currentMonthCheckInCount) 次运动打卡" : "本月尚未开始运动打卡"
        let icon = hasCheckIns ? "checkmark.seal.fill" : "calendar.badge.clock"
        let color = hasCheckIns ? ReferenceColor.green : Color.secondary
        return ReferenceCard {
            VStack(alignment: .leading, spacing: 7) {
                ReferenceSectionTitle(title: "本月打卡", trailing: "查看记录", action: { selectedMoment = "本月运动打卡记录" })
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text("打卡记录会自动保存并同步。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }
    @ViewBuilder private var courseSections: some View {
        if state.usesRemoteDataSource {
            ReferenceSectionTitle(title: "课程动态", trailing: "进入课程", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            EmptyStateView(title: "暂无课程动态", detail: "学校或平台分配课程后会显示在这里。")
                .padding(.horizontal, 12)
        } else {
            ReferenceSectionTitle(title: "延时课堂精彩瞬间", trailing: "查看全部", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            HStack(spacing: 8) {
                moment("ActivityFootball", "足球启蒙")
                moment("ActivityClassroom", "健康课堂")
                moment("ActivityBalance", "亲子平衡")
            }
            .padding(.horizontal, 12)
            ReferenceSectionTitle(title: "推荐课程", trailing: "查看详情", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            CourseSuggestionBanner().padding(.horizontal, 12)
            ReferenceSectionTitle(title: "我的课程", trailing: "全部课程", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            UpcomingTrainingCard(action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
        }
    }
    private var visiblePosts: [ClassPostDraft] {
        state.localFeatures.classPosts.filter { post in
            selectedFilter == "全部"
                || (selectedFilter == "老师动态" && post.authorRole == "teacher")
                || (selectedFilter == "家长分享" && post.authorRole != "teacher")
        }
    }
    @ViewBuilder private var postsFeed: some View {
        if state.usesRemoteDataSource, state.classPostsLoading {
            ProgressView("正在加载班级动态…").frame(maxWidth: .infinity).padding(.vertical, 18)
        } else if state.usesRemoteDataSource, let error = state.classPostsError {
            ErrorStateView(message: error) { Task { await state.loadClassPosts() } }
                .padding(.horizontal, 12)
        } else if state.usesRemoteDataSource, visiblePosts.isEmpty {
            EmptyStateView(title: "暂无班级动态", detail: "学校发布或家长分享后会显示在这里。")
                .padding(.horizontal, 12)
        }
        // 置顶通知属于班级的固定信息，不应在家长发布动态后消失；仅在“家长分享”筛选中隐藏。
        if !state.usesRemoteDataSource && selectedFilter != "家长分享" {
            pinnedAnnouncementPost(
                author: classTeacherName,
                content: "本周运动打卡已开启，欢迎家长分享孩子的练习瞬间。",
                isTeacher: true,
                isLiked: Binding(
                    get: { state.localFeatures.likedClassPostIDs.contains(pinnedNoticeID) },
                    set: { desired in
                        let current = state.localFeatures.likedClassPostIDs.contains(pinnedNoticeID)
                        if desired != current { state.toggleClassPostLike(pinnedNoticeID) }
                    }
                ),
                commentCount: state.localFeatures.classPostComments.filter { $0.postID == pinnedNoticeID }.count,
                comments: state.localFeatures.classPostComments.filter { $0.postID == pinnedNoticeID },
                onComment: { openComment(for: pinnedNoticeID) }
            )
        }
        ForEach(visiblePosts) { post in
            ClassPostCard(
                post: post,
                // Server ownership controls edit/delete. Display names are
                // anonymized and are never used as an ownership key.
                isOwner: post.ownedByCurrentUser || (post.postID == nil && post.status != .submitted),
                isLiked: state.localFeatures.likedClassPostIDs.contains(post.id),
                comments: state.localFeatures.classPostComments.filter { $0.postID == post.id },
                onEdit: { editingPost = post },
                onToggleLike: { state.toggleClassPostLike(post.id) },
                onComment: { openComment(for: post.id) },
                onDelete: { Task { _ = await state.deleteClassPostCommand(post) } },
                onReport: { Task { _ = await state.reportClassPostCommand(post) } }
            )
        }
    }
    private func pinnedAnnouncementPost(author: String, content: String, isTeacher: Bool, isLiked: Binding<Bool>, commentCount: Int, comments: [ClassPostComment], onComment: @escaping () -> Void) -> some View { ReferenceCard { VStack(alignment: .leading, spacing: 7) { HStack { Image(systemName: isTeacher ? "graduationcap.circle.fill" : "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(ReferenceColor.blue); VStack(alignment: .leading, spacing: 1) { Text(author).font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text("今天 08:30 · 本班可见").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Text("置顶").font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.yellow) }; Text(content).font(.system(size: 12)).foregroundStyle(ReferenceColor.navy); HStack { Button { isLiked.wrappedValue.toggle() } label: { Label(isLiked.wrappedValue ? "已赞" : "点赞", systemImage: isLiked.wrappedValue ? "hand.thumbsup.fill" : "hand.thumbsup") }.buttonStyle(.plain); Button(action: onComment) { Label("评论 \(3 + commentCount)", systemImage: "bubble.left") }.buttonStyle(.plain); Spacer(); ShareLink(item: content) { Label("分享", systemImage: "square.and.arrow.up") } }.font(.system(size: 12, weight: .semibold)).foregroundStyle(isLiked.wrappedValue ? ReferenceColor.blue : .secondary); commentPreview(comments) }.accessibilityElement(children: .contain) }.padding(.horizontal, 12) }
    @ViewBuilder private func commentPreview(_ comments: [ClassPostComment]) -> some View {
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Divider()
                Text("最新评论").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(comments.suffix(2))) { comment in
                    Text("\(comment.author)：\(comment.text)").font(.system(size: 12)).foregroundStyle(ReferenceColor.navy).lineLimit(2)
                }
            }
            .padding(.top, 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("最新评论，\(comments.count)条")
        }
    }
    private func classmate(_ student: Student) -> some View {
        let isBoundChild = student.id == state.selectedChild?.id
        let displayName = isBoundChild ? student.name : "\(student.name.prefix(1))同学"
        return VStack(spacing: 4) {
            Text(String(student.name.prefix(1))).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36).background(ReferenceColor.blue.opacity(0.85), in: Circle())
            Text(displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(student.className).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isBoundChild ? "当前孩子 \(student.name)，\(student.className)" : "本班同学，\(student.className)")
    }
    private func moment(_ image: String, _ title: String) -> some View { Button { selectedMoment = title } label: { VStack(alignment: .leading, spacing: 4) { Image(image).resizable().scaledToFill().frame(height: 48).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 7)); Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.navy) }.frame(maxWidth: .infinity) }.buttonStyle(.plain) }
    private static let monthKeyFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"; return formatter }()
}

private struct ClassPostCard: View {
    @EnvironmentObject private var state: AppState
    let post: ClassPostDraft
    let isOwner: Bool
    let isLiked: Bool
    let comments: [ClassPostComment]
    let onEdit: () -> Void
    let onToggleLike: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    var body: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 7) {
                header
                Text(post.content)
                    .font(.system(size: 12))
                    .foregroundStyle(ReferenceColor.navy)
                if let attachments = post.attachments, !attachments.isEmpty {
                    attachmentPreview(attachments)
                }
                actions
                commentPreview
            }
        }
        .padding(.horizontal, 12)
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(ReferenceColor.sky)
            VStack(alignment: .leading, spacing: 1) {
                Text(post.author)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ReferenceColor.blue)
                Text("刚刚发布 · \(syncLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(post.status == .failed ? Color.red : Color.secondary)
            }
            Spacer()
            if isOwner {
                HStack(spacing: 8) {
                    Button("编辑", action: onEdit)
                        .foregroundStyle(ReferenceColor.blue)
                    Button("删除", action: onDelete)
                        .foregroundStyle(.red)
                }
                .font(.system(size: 12, weight: .semibold))
            } else {
                Button("举报", action: onReport)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(action: onToggleLike) {
                Label(isLiked ? "已赞" : "点赞", systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.plain)
            Button(action: onComment) {
                Label("评论", systemImage: "bubble.left")
            }
            .buttonStyle(.plain)
            Spacer()
            ShareLink(item: post.content) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isLiked ? ReferenceColor.blue : Color.secondary)
    }

    @ViewBuilder private func attachmentPreview(_ attachments: [ClassPostAttachment]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
            ForEach(attachments) { attachment in
                Button {
                    Task { await state.loadClassPostAttachment(fileID: attachment.objectID ?? "") }
                } label: {
                    if let objectID = attachment.objectID, let data = state.classPostAttachmentData[objectID], let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: attachment.type == "video" ? "video.fill" : "photo").font(.system(size: 18, weight: .semibold))
                            Text(state.classPostAttachmentErrors[attachment.objectID ?? ""] == nil ? "查看附件" : "加载失败，重试").font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .foregroundStyle(state.classPostAttachmentErrors[attachment.objectID ?? ""] == nil ? ReferenceColor.blue : Color.red)
                        .background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(attachment.type == "video" ? "查看班级圈视频附件" : "查看班级圈图片附件")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(attachments.count) 个班级圈附件，点击可查看")
    }

    @ViewBuilder private var commentPreview: some View {
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Divider()
                Text("最新评论")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(comments.suffix(2))) { comment in
                    Text("\(comment.author)：\(comment.text)")
                        .font(.system(size: 12))
                        .foregroundStyle(ReferenceColor.navy)
                        .lineLimit(2)
                }
            }
            .padding(.top, 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("最新评论，\(comments.count)条")
        }
    }

    private var syncLabel: String {
        switch post.status {
        case .submitted: "已同步"
        case .failed: "同步失败，可在设置中重试"
        case .submitting: "正在同步"
        case .draft: "未完成"
        case .pendingSync: "已保存，联网后自动同步"
        }
    }
}

private struct CommentSheetItem: Identifiable { let id: UUID }

private struct CircleInfoSheet: View {
    let title: String
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    private var currentMonthCheckInCount: Int {
        state.localFeatures.checkInDates.filter { $0.hasPrefix(Self.monthKeyFormatter.string(from: .now)) }.count
    }
    var body: some View {
        NavigationStack {
            List {
                if title.contains("评论") {
                    Section("班级通知评论") {
                        Text("你可以在班级通知下留言，与老师和家长交流。")
                        Text("请注意保护孩子隐私，避免发布个人敏感信息。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if title.contains("互动") {
                    Section("本班互动说明") {
                        Text("仅展示当前本班可见学生名单，便于家长确认交流范围。")
                        Text("班级评优、排名及表彰由学校和班主任统一发布，本页不生成。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("\(state.selectedChild?.name ?? "孩子")的运动打卡") {
                        LabeledContent("本月完成", value: "\(currentMonthCheckInCount) 次")
                        Text(currentMonthCheckInCount == 0 ? "完成一次家庭运动后即可打卡。" : "打卡记录会自动保存并同步。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
    private static let monthKeyFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"; return formatter }()
}
