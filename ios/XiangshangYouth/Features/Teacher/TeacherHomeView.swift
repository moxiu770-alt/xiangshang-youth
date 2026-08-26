import SwiftUI

/// Teacher root tabs are isolated from the detail/dashboard implementations
/// so account capability changes do not require editing the large teacher
/// workflow file.
struct TeacherHomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTab = 0

    private var isSportsTeacher: Bool { state.localFeatures.teacherUsesSportsWorkbench }
    private var canUseSportsWorkbench: Bool { state.teacherHasCapability("UPLOAD_AFTER_SCHOOL_COURSE") }
    private var sportsTeacherBinding: Binding<Bool> {
        Binding(get: { state.localFeatures.teacherUsesSportsWorkbench }, set: { state.setTeacherSportsWorkbench($0) })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TeacherDashboard(isSportsTeacher: sportsTeacherBinding)
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)
            Group {
                if isSportsTeacher && canUseSportsWorkbench {
                    SportsUploadDashboard()
                } else {
                    TeacherClassCircleDashboard()
                }
            }
            .tabItem {
                Label(
                    isSportsTeacher && canUseSportsWorkbench ? "延时上传" : "班级圈",
                    systemImage: isSportsTeacher && canUseSportsWorkbench ? "camera.fill" : "rectangle.grid.2x2"
                )
            }
            .tag(1)
            AccountDashboard()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(2)
        }
        .tint(ReferenceColor.blue)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .onAppear {
            if !canUseSportsWorkbench && isSportsTeacher {
                state.setTeacherSportsWorkbench(false)
            }
        }
    }
}
