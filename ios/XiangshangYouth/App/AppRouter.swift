import SwiftUI

enum AssessmentCategory: String, Hashable, CaseIterable { case fitness = "体质"; case vision = "视力"; case oral = "口腔"; case mental = "心理"
    var icon: String { switch self { case .fitness: "figure.run"; case .vision: "eye.fill"; case .oral: "mouth.fill"; case .mental: "heart.fill" } }
    var color: Color { switch self { case .fitness: ReferenceColor.blue; case .vision: ReferenceColor.green; case .oral: ReferenceColor.yellow; case .mental: ReferenceColor.pink } }
}

enum AppRoute: Hashable { case roleSelect; case parentHome; case parentCourses; case children; case parentEvaluations; case parentMessages; case notifications; case healthProfile; case assessment(AssessmentCategory); case expertList; case teacherHome; case teacherMessages; case teacherClasses; case teacherClassBoard; case studentList(ClassInfo?); case teacherTasks; case teacherTaskDetail(TestTask); case reviewList; case principalHome; case gradeStats; case classStats; case riskStudents; case report(Student) }

@MainActor final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()
    /// Transient scope passed from principal drill-down cards into the next dashboard.
    var pendingGradeFilter: String?
    var pendingClassFilter: String?
    private var pendingDeepLink: URL?
    /// Role dashboards are the root content selected by AppState. Do not push a
    /// second dashboard onto NavigationStack, otherwise iOS shows a back button
    /// and popping it leaves the selected role unchanged.
    func start(_ role: UserRole) { path = NavigationPath() }
    func push(_ route: AppRoute) { path.append(route) }
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
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

        switch target {
        case "report":
            state.selectRole(.parent)
            if let studentID, let student = state.data?.students.first(where: { $0.id == studentID }) { state.selectChild(student) }
            if let student = state.selectedChild { path.append(AppRoute.report(student)) }
        case "review":
            state.selectRole(.teacher)
            path.append(AppRoute.reviewList)
        case "tasks":
            state.selectRole(.teacher)
            path.append(AppRoute.teacherTasks)
        case "risk":
            state.selectRole(.principal)
            path.append(AppRoute.riskStudents)
        default:
            return
        }
        pendingDeepLink = nil
    }
}
