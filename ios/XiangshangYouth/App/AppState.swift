import SwiftUI
import Network

@MainActor final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOffline = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xiangshang.youth.network-monitor")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

@MainActor final class AppState: ObservableObject {
    @Published var isShowingSplash = true
    @Published var profile: UserProfile?
    @Published var selectedRole: UserRole?
    @Published var data: DashboardData?
    @Published var selectedChild: Student?
    @Published var loading = false
    /// Session restoration happens behind the launch artwork. Keeping this separate
    /// from `loading` prevents the retry overlay from flashing before login/role
    /// selection is ready.
    @Published private(set) var restoringSession = false
    @Published var error: String?
    @Published private(set) var localFeatures: LocalFeatureState
    let repository: YouthRepository
    let featureStore: LocalFeatureStore
    init(repository: YouthRepository = RepositoryProvider.make(), featureStore: LocalFeatureStore? = nil) {
        self.repository = repository
        let resolvedFeatureStore = featureStore ?? LocalFeatureStore()
        self.featureStore = resolvedFeatureStore
        // UI smoke tests must not inherit a developer's previous session or
        // bound-child state. This flag is inert for normal and release launches.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            resolvedFeatureStore.reset()
        }
        self.localFeatures = resolvedFeatureStore.state
        if let sessionProfile = localFeatures.sessionProfile {
            profile = sessionProfile
            // Keep the login session, but require an explicit role choice on the
            // next launch so a previously selected principal account cannot lock
            // the user out of the parent or teacher workbench.
            selectedRole = nil
            Task { [weak self] in
                guard let self else { return }
                self.restoringSession = true
                self.loading = true
                defer {
                    self.loading = false
                    self.restoringSession = false
                }
                do {
                    self.data = try await repository.loadDashboard()
                    self.selectedChild = self.data?.students.first(where: { $0.id == self.localFeatures.selectedChildID && self.localFeatures.boundChildIDs.contains($0.id) })
            } catch {
                if case ApiError.unauthorized = error {
                    self.handleDashboardError(error)
                } else {
                    // A persisted session is only useful when its dashboard can be
                    // refreshed.  Do not send the user into role selection with a
                    // nil dashboard (which would leave every workbench loading
                    // forever); return to login with an actionable error instead.
                    self.mutateLocal { values in
                        values.sessionProfile = nil
                        values.sessionRole = nil
                    }
                    self.profile = nil
                    self.selectedRole = nil
                    self.selectedChild = nil
                    self.data = nil
                    self.error = error.localizedDescription
                }
            }
            }
        }
        // Local visual-regression entry point.  It is inert unless Xcode/simctl passes
        // XS_DEBUG_ROLE, so production launch always retains splash → login → role flow.
        let debugRole: UserRole? = switch ProcessInfo.processInfo.environment["XS_DEBUG_ROLE"] {
        case "parent", UserRole.parent.rawValue: .parent
        case "teacher", UserRole.teacher.rawValue: .teacher
        case "principal", UserRole.principal.rawValue: .principal
        default: nil
        }
        if let role = debugRole {
            isShowingSplash = false
            selectedRole = role
            profile = UserProfile(id: "debug", name: role == .teacher ? "李老师" : role == .principal ? "周校长" : "王女士", phone: "13800138000", role: role, schoolName: "向上实验小学", avatarInitials: role == .teacher ? "李" : role == .principal ? "周" : "王")
            Task { [weak self] in
                guard let self else { return }
                self.data = try? await repository.loadDashboard()
                self.selectedChild = self.data?.students.first(where: { $0.id == self.localFeatures.selectedChildID && self.localFeatures.boundChildIDs.contains($0.id) })
            }
        }
    }
    func dismissSplash() { isShowingSplash = false }
    func login(phone: String) async {
        loading = true
        error = nil
        defer { loading = false }
        let candidate = UserProfile(id: "u1", name: "王女士", phone: phone, role: .parent, schoolName: "向上实验小学", avatarInitials: "王")
        do {
            // Commit the session only after the dashboard has loaded. A failed login
            // therefore stays on the form and can show its error inline instead of
            // jumping to an empty role screen.
            data = try await repository.loadDashboard()
            profile = candidate
            selectedChild = data?.students.first(where: { $0.id == localFeatures.selectedChildID && localFeatures.boundChildIDs.contains($0.id) })
            persistSession()
            persistSelectedChild()
        } catch { self.handleDashboardError(error) }
    }
    func refreshDashboard() async {
        guard profile != nil, !loading else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            data = try await repository.loadDashboard()
            if let selectedChild, let refreshed = data?.students.first(where: { $0.id == selectedChild.id }) { self.selectedChild = refreshed }
            else { selectedChild = nil }
        } catch { self.handleDashboardError(error) }
    }
    func selectRole(_ role: UserRole) { selectedRole = role; if var profile { profile = UserProfile(id: profile.id, name: role == .teacher ? "李老师" : role == .principal ? "周校长" : "王女士", phone: profile.phone, role: role, schoolName: profile.schoolName, avatarInitials: role == .teacher ? "李" : role == .principal ? "周" : "王"); self.profile = profile; persistSession() } }
    func chooseAnotherRole() { selectedRole = nil }
    func switchAccount() { ApiClient.shared.token = nil; featureStore.reset(); localFeatures = featureStore.state; profile = nil; selectedRole = nil; selectedChild = nil; data = nil; error = nil }
    func report(for student: Student) -> DiagnosisReport { repository.report(for: student) }
    func selectChild(_ student: Student) { selectedChild = student; persistSelectedChild() }
    var boundChildren: [Student] {
        guard let data else { return [] }
        return data.students.filter { localFeatures.boundChildIDs.contains($0.id) }
    }
    var unreadMessageCount: Int {
        guard localFeatures.settings.notificationsEnabled else { return 0 }
        return (data?.messages ?? []).filter { !$0.isRead && !localFeatures.readMessageIDs.contains($0.id) }.count
    }
    /// Local writes that have not been acknowledged by a remote service yet.
    var pendingSyncCount: Int {
        let activity = localFeatures.activityRegistrations.count(where: { $0.status == .pendingSync })
        let experts = localFeatures.expertAppointments.count(where: { $0.status == .pendingSync })
        let uploads = localFeatures.courseUploads.count(where: { $0.status == .pendingSync })
        return activity + experts + uploads
    }
    func markMessageRead(_ id: String) { mutateLocal { $0.readMessageIDs.insert(id) } }
    @discardableResult
    func bindChild(name: String, code: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedName.isEmpty, !normalizedCode.isEmpty,
              let child = data?.students.first(where: { student in
                  let validCode = normalizedCode == student.id.uppercased() || normalizedCode == "XS-\(student.id.uppercased())"
                  return validCode && student.name == normalizedName
              }) else { return false }
        mutateLocal { $0.boundChildIDs.insert(child.id) }
        if selectedChild == nil { selectChild(child) }
        return true
    }

    func registerActivity(_ id: String, contactName: String, phone: String) {
        guard !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, phone.filter(\.isNumber).count == 11 else { return }
        mutateLocal { values in
            values.registeredActivities.insert(id)
            values.activityRegistrations.removeAll { $0.activityID == id }
            values.activityRegistrations.insert(ActivityRegistration(id: UUID(), activityID: id, contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone, status: .pendingSync, createdAt: .now), at: 0)
        }
    }
    func completeAssessment(_ category: AssessmentCategory) { mutateLocal { $0.completedAssessments.insert("\(selectedChild?.id ?? "anonymous")-\(category.rawValue)") } }
    func updateCourseProgress(_ title: String, progress: Double) { mutateLocal { $0.courseProgress[title] = progress } }
    func sendSupportMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mutateLocal { values in
            values.supportMessages.append(SupportChatMessage(id: UUID(), text: text, isMine: true, createdAt: .now))
            values.supportMessages.append(SupportChatMessage(id: UUID(), text: "已收到您的咨询，客服老师会在工作时间内为您回复。", isMine: false, createdAt: .now))
        }
    }
    func publishClassPost(_ text: String, author: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mutateLocal { $0.classPosts.insert(ClassPostDraft(id: UUID(), author: author, content: text, createdAt: .now), at: 0) }
    }
    func updateClassPost(id: UUID, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mutateLocal { values in
            guard let index = values.classPosts.firstIndex(where: { $0.id == id }) else { return }
            values.classPosts[index].content = text
        }
    }
    func toggleClassPostLike(_ id: UUID) {
        mutateLocal { values in
            if values.likedClassPostIDs.contains(id) { values.likedClassPostIDs.remove(id) }
            else { values.likedClassPostIDs.insert(id) }
        }
    }
    func addClassPostComment(postID: UUID, text: String, author: String = "王女士") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateLocal { values in
            values.classPostComments.append(ClassPostComment(id: UUID(), postID: postID, author: author, text: trimmed, createdAt: .now))
        }
    }
    func saveDraft(_ text: String, key: String) { mutateLocal { $0.drafts[key] = text } }
    func clearDraft(_ key: String) { mutateLocal { $0.drafts.removeValue(forKey: key) } }
    func clearDrafts(prefix: String) { mutateLocal { values in let keys = values.drafts.keys.filter { $0.hasPrefix(prefix) }; keys.forEach { values.drafts.removeValue(forKey: $0) } } }
    func bookExpert(name: String, preferredDate: String, note: String) {
        guard !preferredDate.isEmpty, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // A family can reopen the same expert card after process restoration.
        // Keep the local command idempotent until the remote appointment API is
        // connected; otherwise repeated taps would create duplicate bookings.
        guard !localFeatures.expertAppointments.contains(where: {
            $0.expertName == name && ($0.status == .pendingSync || $0.status == .submitted)
        }) else { return }
        mutateLocal { $0.expertAppointments.insert(ExpertAppointment(id: UUID(), expertName: name, preferredDate: preferredDate, note: note, status: .pendingSync, createdAt: .now), at: 0) }
    }
    func saveCourseUpload(taskID: String, attendanceCount: Int, notes: String, attachmentName: String, submit: Bool) {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard attendanceCount >= 0, (!submit || (!trimmedNotes.isEmpty && !attachmentName.isEmpty)) else { return }
        mutateLocal { values in
            let status: LocalSubmissionStatus = submit ? .pendingSync : .draft
            let record = CourseUploadRecord(id: UUID(), taskID: taskID, attendanceCount: attendanceCount, notes: trimmedNotes, attachmentName: attachmentName, status: status, createdAt: .now)
            values.courseUploads.removeAll { $0.taskID == taskID }
            values.courseUploads.insert(record, at: 0)
            if submit { values.uploadedTaskIDs.insert(taskID) }
        }
    }
    func taskStatus(for student: Student) -> TaskStatus { localFeatures.studentTaskStatuses[student.id] ?? student.taskStatus }
    func updateTaskStatus(for student: Student, status: TaskStatus, reviewNote: String? = nil) {
        let trimmedNote = reviewNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        mutateLocal {
            $0.studentTaskStatuses[student.id] = status
            if !trimmedNote.isEmpty { $0.reviewNotes[student.id] = trimmedNote }
        }
    }
    func updateSettings(notificationsEnabled: Bool? = nil, reduceMotion: Bool? = nil) {
        mutateLocal { values in
            if let notificationsEnabled { values.settings.notificationsEnabled = notificationsEnabled }
            if let reduceMotion { values.settings.reduceMotion = reduceMotion }
        }
    }
    func submitUpload(taskID: String) { saveCourseUpload(taskID: taskID, attendanceCount: 0, notes: "已确认课后测评记录", attachmentName: "课堂记录.jpg", submit: true) }
    func checkInToday() { mutateLocal { $0.checkInDates.insert(Self.dayFormatter.string(from: .now)) } }
    private func persistSession() { mutateLocal { values in values.sessionProfile = profile; values.sessionRole = selectedRole } }
    private func persistSelectedChild() { mutateLocal { values in values.selectedChildID = selectedChild?.id } }
    private func handleDashboardError(_ error: Error) {
        if case ApiError.cancelled = error { return }
        if case ApiError.unauthorized = error {
            ApiClient.shared.token = nil
            featureStore.reset()
            localFeatures = featureStore.state
            profile = nil
            selectedRole = nil
            selectedChild = nil
            data = nil
        }
        self.error = error.localizedDescription
    }
    private func mutateLocal(_ body: (inout LocalFeatureState) -> Void) { featureStore.update(body); localFeatures = featureStore.state }
    private static let dayFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = .current; formatter.locale = .current; formatter.dateFormat = "yyyy-MM-dd"; return formatter }()
}
