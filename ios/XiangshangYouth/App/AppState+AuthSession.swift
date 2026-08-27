import SwiftUI

@MainActor extension AppState {
    func dismissSplash() { isShowingSplash = false }
    func beginWechatAuthorization() async -> URL? {
        guard !loading, repository.supportsRemoteAcknowledgement else { return nil }
        loading = true; error = nil
        defer { loading = false }
        do { return try await AuthApi().startWechatAuthorization().authorizeUrl }
        catch { handleDashboardError(error); return nil }
    }
    /// Starts an account session. `accountRole` is supplied by registration
    /// when a new account is assigned to a workbench bucket; ordinary login
    /// keeps the existing parent-compatible mock behaviour until AuthApi is live.
    func login(phone: String, verificationCode: String? = nil, password: String? = nil, displayName: String? = nil, accountRole: UserRole? = nil) async {
        // A double tap on a third-party login button can otherwise create two
        // overlapping dashboard loads.  Keep the existing page responsive and
        // make the in-button progress indicator the single source of feedback.
        guard !loading else { return }
        if repository.supportsRemoteAcknowledgement, phone == "wechat_authorization" {
            error = "微信登录尚未配置正式 AppID 与服务端授权回调，请使用短信或账号密码登录。"
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        // Third-party authorization does not expose a raw phone number to this
        // screen. Keep its internal identifier out of the account profile until
        // the real WeChat bind endpoint returns the verified mobile number.
        if repository.supportsRemoteAcknowledgement {
            do {
                let session = try await AuthApi().login(phone: phone, verificationCode: verificationCode, password: password)
                repository.configureSession(session.profile)
                data = try await repository.loadDashboard()
                profile = session.profile
                selectedRole = session.profile.role
                mutateLocal { values in
                    values.accountBucket = session.profile.role
                    values.parentAccountName = session.profile.role == .parent ? session.profile.name : values.parentAccountName
                }
                reconcileSelectedChildFromDashboard()
                refreshSelectedChildRemoteData()
                persistSession()
                persistSelectedChild()
            } catch { self.handleDashboardError(error) }
            return
        }
        let displayPhone = phone == "wechat_authorization" ? "未绑定手机号" : phone
        let normalizedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = normalizedName.flatMap { $0.isEmpty ? nil : $0 } ?? "王女士"
        let avatarInitial = String(name.prefix(1))
        let bucket = accountRole ?? .parent
        let candidateID = bucket == .teacher ? "teacher_li" : (bucket == .parent ? "parent_wang" : "principal_zhou")
        let candidateCapabilities = bucket == .teacher ? ["VIEW_CLASS_DASHBOARD", "MANAGE_CLASS_STUDENTS", "VIEW_TEST_TASKS", "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST", "UPLOAD_AFTER_SCHOOL_COURSE", "PUBLISH_CLASS_NOTICE"] : []
        let candidateClasses = bucket == .teacher ? ["c31", "c32"] : []
        // Mock/offline login is a family-login fallback, not an implicit
        // teacher credential.  The role selector must only reflect an actual
        // session claim (or an explicit debug fixture), otherwise any newly
        // registered parent could open the teacher workbench before a school
        // administrator grants that role on the server.
        let candidate = UserProfile(id: candidateID, name: name, phone: displayPhone, role: bucket, schoolName: "向上实验小学", avatarInitials: avatarInitial, availableRoles: [bucket], authorizedClassIDs: candidateClasses, capabilities: candidateCapabilities)
        do {
            // Commit the session only after the dashboard has loaded. A failed login
            // therefore stays on the form and can show its error inline instead of
            // jumping to an empty role screen.
            data = try await repository.loadDashboard()
            profile = candidate
            selectedRole = accountRole
            mutateLocal { values in
                values.accountBucket = accountRole ?? values.accountBucket ?? .parent
                if bucket == .parent { values.parentAccountName = name }
            }
            reconcileSelectedChildFromDashboard()
            refreshSelectedChildRemoteData()
            persistSession()
            persistSelectedChild()
        } catch { self.handleDashboardError(error) }
    }

    /// Completes the one-time native callback relayed by the central service.
    func exchangeWechat(code: String, state: String) async {
        guard !loading, !code.isEmpty, !state.isEmpty, repository.supportsRemoteAcknowledgement else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let session = try await AuthApi().exchangeWechat(code: code, state: state)
            repository.configureSession(session.profile)
            data = try await repository.loadDashboard()
            profile = session.profile
            selectedRole = session.profile.role
            mutateLocal { values in
                values.accountBucket = session.profile.role
                values.parentAccountName = session.profile.role == .parent ? session.profile.name : values.parentAccountName
            }
            reconcileSelectedChildFromDashboard()
            refreshSelectedChildRemoteData()
            persistSession(); persistSelectedChild()
        } catch { handleDashboardError(error) }
    }
    /// Registration has its own remote contract.  It must not silently fall
    /// through to login, otherwise the password and account bucket are lost.
    func register(name: String, phone: String, verificationCode: String, password: String, role: UserRole) async {
        guard !loading else { return }
        guard role == .parent else {
            error = "教师账号须由学校管理员开通后登录，不能自助注册。"
            return
        }
        guard repository.supportsRemoteAcknowledgement else {
            await login(phone: phone, verificationCode: verificationCode, password: password, displayName: name, accountRole: role)
            return
        }
        loading = true; error = nil; defer { loading = false }
        do {
            let session = try await AuthApi().register(name: name, phone: phone, verificationCode: verificationCode, password: password, role: role)
            repository.configureSession(session.profile)
            data = try await repository.loadDashboard()
            profile = session.profile
            selectedRole = session.profile.role
            mutateLocal { values in
                values.accountBucket = session.profile.role
                if session.profile.role == .parent { values.parentAccountName = session.profile.name }
            }
            reconcileSelectedChildFromDashboard()
            refreshSelectedChildRemoteData()
            persistSession(); persistSelectedChild()
        } catch { handleDashboardError(error) }
    }
    func resetPassword(phone: String, verificationCode: String, password: String) async -> Bool {
        guard repository.supportsRemoteAcknowledgement else { return true }
        do { try await AuthApi().resetPassword(phone: phone, verificationCode: verificationCode, password: password); return true }
        catch let resetError { self.error = resetError.localizedDescription; return false }
    }
    func requestVerificationCode(account: String, purpose: String) async -> Bool {
        guard account.filter(\.isNumber).count == 11 else { error = "请输入有效的 11 位手机号。"; return false }
        guard repository.supportsRemoteAcknowledgement else { return true }
        do { try await AuthApi().sendVerificationCode(account: account, purpose: purpose); error = nil; return true }
        catch let requestError { error = requestError.localizedDescription; return false }
    }
    func refreshDashboard() async {
        guard profile != nil, !loading, !isOffline else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            data = try await repository.loadDashboard()
            studentsLoadError = nil
            reconcileSelectedChildFromDashboard()
            refreshSelectedChildRemoteData()
        } catch { self.handleDashboardError(error) }
    }
    /// Fetches the next remote student-directory page without replacing the
    /// already visible dashboard.  Aggregate cards remain school-wide while
    /// large teacher directories grow incrementally.
    func loadMoreStudents() async {
        guard !studentsLoadingMore, !loading, !isOffline,
              let current = data,
              let total = current.studentTotal,
              let page = current.studentPage,
              let pageSize = current.studentPageSize,
              total > current.students.count else { return }
        let nextPage = page + 1
        guard (nextPage - 1) * pageSize < total else { return }
        studentsLoadingMore = true
        studentsLoadError = nil
        defer { studentsLoadingMore = false }
        do {
            let next = try await repository.loadDashboard(studentPage: nextPage, studentPageSize: pageSize)
            var merged = current.students
            let existing = Set(merged.map(\.id))
            merged.append(contentsOf: next.students.filter { !existing.contains($0.id) })
            data = DashboardData(school: next.school, students: merged, classes: next.classes, grades: next.grades, tasks: next.tasks, parentChildren: next.parentChildren, messages: next.messages, studentTotal: next.studentTotal ?? total, studentPage: next.studentPage ?? nextPage, studentPageSize: next.studentPageSize ?? pageSize)
        } catch {
            if case ApiError.unauthorized = error { handleDashboardError(error) }
            else { studentsLoadError = error.localizedDescription }
        }
    }
    func clearError() { error = nil }
    /// A role is a server-owned account grant.  `mobileRoles` describes which
    /// workbenches exist in the app; it must never be used as a fallback grant.
    @discardableResult
    func selectRole(_ role: UserRole) -> Bool {
        guard profile?.availableRoles.contains(role) == true else { return false }
        if selectedRole != role { taskRosterRecords.removeAll() }
        selectedRole = role
        if var profile {
            // Builds released before `parentAccountName` existed may already
            // have a real parent profile in the session payload. Capture it
            // before replacing the visible identity with a teacher/principal
            // workbench name, otherwise the first post-upgrade role switch
            // would silently reset that family name to the mock default.
            if localFeatures.parentAccountName == nil, profile.role == .parent {
                mutateLocal { $0.parentAccountName = profile.name }
            }
            let parentName = localFeatures.parentAccountName ?? (profile.role == .parent ? profile.name : "家长")
            // Keep the authenticated identity when changing workbenches. The
            // Mock teacher account has no separate credential, so its display
            // name is taken from the managed class data instead of being
            // hard-coded into session state.
            let name: String
            if repository.supportsRemoteAcknowledgement {
                // A remote account owns one stable identity across its granted
                // workbenches. Never replace it with a bundled demo teacher.
                name = profile.name
            } else {
                switch role {
                case .parent: name = parentName
                case .teacher: name = profile.role == .teacher ? profile.name : "李老师"
                case .principal: name = profile.name
                }
            }
            profile = UserProfile(
                id: profile.id,
                name: name,
                phone: profile.phone,
                role: role,
                schoolName: profile.schoolName,
                avatarInitials: String(name.prefix(1)),
                roleCode: profile.roleCode,
                schoolID: profile.schoolID,
                availableRoles: profile.availableRoles,
                authorizedClassIDs: role == .teacher && !repository.supportsRemoteAcknowledgement && profile.authorizedClassIDs.isEmpty ? ["c31", "c32"] : profile.authorizedClassIDs,
                capabilities: role == .teacher && !repository.supportsRemoteAcknowledgement && profile.capabilities.isEmpty ? ["VIEW_CLASS_DASHBOARD", "MANAGE_CLASS_STUDENTS", "VIEW_TEST_TASKS", "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST", "UPLOAD_AFTER_SCHOOL_COURSE", "PUBLISH_CLASS_NOTICE"] : profile.capabilities
            )
            self.profile = profile
            persistSession()
        }
        return true
    }
    func chooseAnotherRole() { selectedRole = nil; taskRosterRecords.removeAll() }
    func selectPrincipalTask(_ taskID: String) { mutateLocal { $0.selectedPrincipalTaskID = taskID } }
}
