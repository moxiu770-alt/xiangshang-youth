import SwiftUI

enum AssessmentCategory: String, Hashable, CaseIterable { case fitness = "体质"; case vision = "视力"; case oral = "口腔"; case mental = "心理"
    var icon: String { switch self { case .fitness: "figure.run"; case .vision: "eye.fill"; case .oral: "mouth.fill"; case .mental: "heart.fill" } }
    var color: Color { switch self { case .fitness: ReferenceColor.blue; case .vision: ReferenceColor.green; case .oral: ReferenceColor.yellow; case .mental: ReferenceColor.pink } }
}

enum AppRoute: Hashable {
    case roleSelect; case backendDashboard; case parentHome; case parentCourses; case children(returnAfterBinding: Bool); case parentEvaluations; case parentTask(TestTask); case parentMessages; case notifications; case healthProfile; case bodyAssessment; case assessment(AssessmentCategory); case activityList; case expertList; case teacherHome; case teacherMessages; case teacherNoticeComposer; case teacherClasses; case teacherClassBoard; case studentList(ClassInfo?); case outstandingStudents; case unassignedStudents; case teacherTasks; case teacherTaskDetail(TestTask); case reviewList; case report(Student)

    /// A bell must never route a family into the teacher inbox. Keep this
    /// mapping next to the route declarations so every header uses the same
    /// role-aware destination.
    static func messageCenter(for role: UserRole?) -> AppRoute {
        switch role {
        case .parent: .parentMessages
        case .teacher: .teacherMessages
        case .principal, .none: .notifications
        }
    }
}

/// A notification URL selects a destination but never grants a new role.
/// Keeping this rule pure makes it testable without constructing a live
/// AppState or network repository.
enum DeepLinkAuthorization {
    static func isAuthorized(target: String, remote: Bool, availableRoles: Set<UserRole>) -> Bool {
        // A local/Mock repository still represents a concrete signed-in
        // account.  Never let the repository mode turn a URL into a teacher
        // grant. `remote` remains part of the public contract for source
        // compatibility, but authorization always depends on role claims.
        switch target {
        case "report": return availableRoles.contains(.parent)
        case "review", "tasks": return availableRoles.contains(.teacher)
        case "risk": return availableRoles.contains(.principal)
        default: return false
        }
    }
}

@MainActor final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()
    /// Mirrors the typed routes we append to NavigationPath. NavigationPath is
    /// intentionally opaque, so keeping this small stack lets us deduplicate a
    /// repeated tap even after a child route has been popped.
    private var routeStack: [AppRoute] = []
    /// Transient scope passed from principal drill-down cards into the next dashboard.
    var pendingGradeFilter: String?
    var pendingClassFilter: String?
    private var pendingDeepLink: URL?
    /// Role dashboards are the root content selected by AppState. Do not push a
    /// second dashboard onto NavigationStack, otherwise iOS shows a back button
    /// and popping it leaves the selected role unchanged.
    func start(_ role: UserRole) {
        path = NavigationPath()
        routeStack.removeAll()
        clearTransientScopes()
    }
    func reset() {
        path = NavigationPath()
        routeStack.removeAll()
        clearTransientScopes()
        pendingDeepLink = nil
    }
    func push(_ route: AppRoute) {
        // Cards, notification bells and retry affordances can be tapped repeatedly
        // before SwiftUI finishes the transition. Keep one instance of the same
        // destination at the top while still allowing a different student/task
        // payload to be opened normally.
        guard routeStack.last != route else { return }
        path.append(route)
        routeStack.append(route)
    }
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
        if !routeStack.isEmpty { routeStack.removeLast() }
    }
    /// SwiftUI can mutate `NavigationPath` directly for an interactive back
    /// swipe or a system back action. Keep the dedupe mirror aligned with the
    /// observable path so the next tap cannot be mistaken for a duplicate.
    func syncStackToPathCount() {
        guard routeStack.count > path.count else { return }
        routeStack.removeLast(routeStack.count - path.count)
    }

    /// Supports notification and browser entry points, for example
    /// xiangshang-youth://open?target=report&studentId=s01.
    func receiveDeepLink(_ url: URL) { pendingDeepLink = url }

    func activatePendingDeepLink(using state: AppState) {
        guard let url = pendingDeepLink,
              url.scheme == "xiangshang-youth",
              url.host == "open" else { return }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let target = query.first(where: { $0.name == "target" })?.value
        if target == "wechat-callback" {
            pendingDeepLink = nil
            guard let code = query.first(where: { $0.name == "code" })?.value,
                  let oauthState = query.first(where: { $0.name == "state" })?.value else { return }
            Task { await state.exchangeWechat(code: code, state: oauthState) }
            return
        }
        guard state.profile != nil, state.data != nil else { return }
        let studentID = query.first(where: { $0.name == "studentId" })?.value
        // Never mutate an active workbench for an unsupported/deprecated
        // deep-link target. A malformed notification should be harmless.
        guard ["report", "review", "tasks", "risk"].contains(target ?? "") else {
            pendingDeepLink = nil
            return
        }
        // An unauthorized notification must not disturb the current
        // workbench. On a cold launch the normal splash/session restoration
        // path will still choose the authenticated role root.
        guard DeepLinkAuthorization.isAuthorized(
            target: target ?? "",
            remote: state.repository.supportsRemoteAcknowledgement,
            availableRoles: Set(state.profile?.availableRoles ?? [])
        ) else {
            pendingDeepLink = nil
            return
        }
        // Consume the URL before changing the published role. SwiftUI may
        // synchronously deliver the role change back through RootView's
        // `onChange`; clearing first prevents that callback from re-entering
        // this method and duplicating the destination.
        pendingDeepLink = nil
        path = NavigationPath()
        routeStack.removeAll()
        clearTransientScopes()

        switch target {
        case "report":
            // Reports are family-scoped. A notification URL must not turn a
            // teacher-only session into a parent session; role availability
            // comes from the authenticated profile, never from the URL.
            guard state.selectRole(.parent) else { return }
            // A family deep link must never turn an arbitrary student id into a
            // selected child.  Only a child already bound to this account can
            // open a report; otherwise take the family to the binding surface.
            if let studentID,
               let student = state.data?.students.first(where: { $0.id == studentID }),
               state.localFeatures.boundChildIDs.contains(student.id) {
                state.selectChild(student)
                let route = AppRoute.report(student)
                path.append(route)
                routeStack.append(route)
            } else {
                path.append(AppRoute.children(returnAfterBinding: true))
                routeStack.append(.children(returnAfterBinding: true))
            }
        case "review":
            // A notification/deep link is untrusted input. Do not let a family
            // account jump into the teacher workbench merely by changing the
            // target query; the backend role grant is the source of truth.
            guard state.selectRole(.teacher) else { return }
            path.append(AppRoute.reviewList)
            routeStack.append(.reviewList)
        case "tasks":
            guard state.selectRole(.teacher) else { return }
            path.append(AppRoute.teacherTasks)
            routeStack.append(.teacherTasks)
        case "risk":
            // Legacy risk links belong to the school-management dashboard.
            // Do not silently turn a family/teacher session into another
            // mobile role; the backend notice will provide the safe exit. It
            // is a workbench root, not a pushed detail page: pushing it here
            // would make SwiftUI render a back button in the top-left and
            // return to the previous role after a risk notification.
            guard state.selectRole(.principal) else { return }
            start(.principal)
        default:
            return
        }
    }

    private func clearTransientScopes() {
        pendingGradeFilter = nil
        pendingClassFilter = nil
    }
}
