import SwiftUI

enum AssessmentCategory: String, Hashable, CaseIterable { case fitness = "体质"; case vision = "视力"; case oral = "口腔"; case mental = "心理"
    var icon: String { switch self { case .fitness: "figure.run"; case .vision: "eye.fill"; case .oral: "mouth.fill"; case .mental: "heart.fill" } }
    var color: Color { switch self { case .fitness: ReferenceColor.blue; case .vision: ReferenceColor.green; case .oral: ReferenceColor.yellow; case .mental: ReferenceColor.pink } }
}

enum AppRoute: Hashable { case roleSelect; case parentHome; case parentCourses; case children(returnAfterBinding: Bool); case parentEvaluations; case parentMessages; case notifications; case healthProfile; case bodyAssessment; case assessment(AssessmentCategory); case expertList; case teacherHome; case teacherMessages; case teacherClasses; case teacherClassBoard; case studentList(ClassInfo?); case outstandingStudents; case unassignedStudents; case teacherTasks; case teacherTaskDetail(TestTask); case reviewList; case principalHome; case gradeStats; case classStats; case riskStudents; case report(Student) }

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
    func start(_ role: UserRole) { path = NavigationPath(); routeStack.removeAll() }
    func reset() { path = NavigationPath(); routeStack.removeAll() }
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
              url.host == "open",
              state.profile != nil,
              state.data != nil else { return }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let target = query.first(where: { $0.name == "target" })?.value
        let studentID = query.first(where: { $0.name == "studentId" })?.value
        path = NavigationPath()
        routeStack.removeAll()

        switch target {
        case "report":
            state.selectRole(.parent)
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
            state.selectRole(.teacher)
            path.append(AppRoute.reviewList)
            routeStack.append(.reviewList)
        case "tasks":
            state.selectRole(.teacher)
            path.append(AppRoute.teacherTasks)
            routeStack.append(.teacherTasks)
        case "risk":
            state.selectRole(.principal)
            path.append(AppRoute.riskStudents)
            routeStack.append(.riskStudents)
        default:
            return
        }
        pendingDeepLink = nil
    }
}
