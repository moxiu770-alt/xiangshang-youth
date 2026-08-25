#!/usr/bin/env python3
"""Static cross-platform frontend release contract.

This is intentionally small and dependency-free.  It verifies the product
boundaries that are easy to regress in a UI refactor: the pure launch poster,
the two mobile workbenches, in-app camera capture, the Mock/Remote seam, and
the backend-dashboard migration for school management.  It is not a visual
snapshot test; device screenshots remain a separate release gate.
"""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"missing required file: {relative}")
    return path.read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"{label}: missing {needle!r}")


def main() -> int:
    for legacy in (
        "android/app/src/main/java/com/xiangshang/youth/feature/principal/PrincipalScreens.kt",
        "ios/XiangshangYouth/Features/Principal/PrincipalViews.swift",
    ):
        if (ROOT / legacy).exists():
            raise AssertionError(f"legacy mobile principal workbench still exists: {legacy}")

    ios_app = read("ios/XiangshangYouth/XiangshangYouthApp.swift")
    ios_info = read("ios/XiangshangYouth/Info.plist")
    ios_router = read("ios/XiangshangYouth/App/AppRouter.swift")
    ios_repo = read("ios/XiangshangYouth/Core/Repositories/RepositoryProvider.swift")
    ios_stats_api = read("ios/XiangshangYouth/Core/Services/StatsApi.swift")
    ios_remote_repo = read("ios/XiangshangYouth/Core/Repositories/RemoteRepository.swift")
    ios_state = read("ios/XiangshangYouth/App/AppState.swift")
    ios_body = read("ios/XiangshangYouth/Features/Parent/LiveVisionCapture.swift")
    ios_body_screen = read("ios/XiangshangYouth/Features/Parent/BodyAssessmentViews.swift")
    ios_parent_screen = read("ios/XiangshangYouth/Features/Parent/ParentViews.swift")
    ios_auth = read("ios/XiangshangYouth/Features/Auth/AuthViews.swift")
    ios_auth_api = read("ios/XiangshangYouth/Core/Services/AuthApi.swift")
    ios_parent_forms = read("ios/XiangshangYouth/Features/Parent/ParentExtendedViews.swift")
    ios_local_store = read("ios/XiangshangYouth/Core/Services/LocalFeatureStore.swift")
    ios_teacher_forms = read("ios/XiangshangYouth/Features/Teacher/TeacherViews.swift")
    ios_business_clock = read("ios/XiangshangYouth/Core/Extensions/BusinessClock.swift")
    ios_student_model = read("ios/XiangshangYouth/Core/Models/Student.swift")
    ios_student_api = read("ios/XiangshangYouth/Core/Services/StudentApi.swift")
    ios_account_deletion_api = read("ios/XiangshangYouth/Core/Services/AccountDeletionApi.swift")
    ios_task_api = read("ios/XiangshangYouth/Core/Services/TaskApi.swift")
    android_activity = read("android/app/src/main/java/com/xiangshang/youth/MainActivity.kt")
    android_manifest = read("android/app/src/main/AndroidManifest.xml")
    android_nav = read("android/app/src/main/java/com/xiangshang/youth/app/AppNavHost.kt")
    android_repo = read("android/app/src/main/java/com/xiangshang/youth/core/repository/RepositoryProvider.kt")
    android_stats_api = read("android/app/src/main/java/com/xiangshang/youth/core/service/StatsApi.kt")
    android_remote_repo = read("android/app/src/main/java/com/xiangshang/youth/core/repository/RemoteRepository.kt")
    android_state = read("android/app/src/main/java/com/xiangshang/youth/app/AppState.kt")
    android_upload_validator = read("android/app/src/main/java/com/xiangshang/youth/core/service/CourseUploadValidator.kt")
    android_body = read("android/app/src/main/java/com/xiangshang/youth/feature/parent/LivePostureCapture.kt")
    android_body_screen = read("android/app/src/main/java/com/xiangshang/youth/feature/parent/BodyAssessmentScreen.kt")
    android_follow_along = read("android/app/src/main/java/com/xiangshang/youth/feature/parent/FollowAlongTraining.kt")
    android_auth = read("android/app/src/main/java/com/xiangshang/youth/feature/auth/AuthScreens.kt")
    android_auth_api = read("android/app/src/main/java/com/xiangshang/youth/core/service/AuthApi.kt")
    android_parent_forms = read("android/app/src/main/java/com/xiangshang/youth/feature/parent/ParentScreens.kt")
    android_local_store = read("android/app/src/main/java/com/xiangshang/youth/core/service/LocalFeatureStore.kt")
    android_teacher_forms = read("android/app/src/main/java/com/xiangshang/youth/feature/teacher/TeacherScreens.kt")
    android_business_clock = read("android/app/src/main/java/com/xiangshang/youth/core/util/BusinessClock.kt")
    android_student_model = read("android/app/src/main/java/com/xiangshang/youth/core/model/Student.kt")
    android_student_api = read("android/app/src/main/java/com/xiangshang/youth/core/service/StudentApi.kt")
    android_account_deletion_api = read("android/app/src/main/java/com/xiangshang/youth/core/service/AccountApi.kt")
    android_task_api = read("android/app/src/main/java/com/xiangshang/youth/core/service/TaskApi.kt")
    android_deep_link = read("android/app/src/main/java/com/xiangshang/youth/core/util/DeepLinkResolver.kt")
    backend_config = read("backend/src/config.js")
    backend_server = read("backend/src/server.js")
    android_gradle = read("android/app/build.gradle.kts")
    ios_ui_tests = read("ios/XiangshangYouthUITests/LaunchAndRoleFlowTests.swift")
    android_ui_tests = read("android/app/src/androidTest/java/com/xiangshang/youth/MainActivityFlowTest.kt")
    mobile_ci = read(".github/workflows/mobile-ci.yml")

    # Launch and navigation contract.
    require(ios_app, "SplashView()", "iOS splash")
    require(ios_app, ".persistentSystemOverlays(state.isShowingSplash ? .hidden : .visible)", "iOS pure poster")
    require(ios_info, "<key>UIStatusBarHidden</key>", "iOS launch chrome")
    require(android_activity, "Type.statusBars() or", "Android launch chrome")
    require(android_nav, "BackendDashboardNoticeScreen", "Android school dashboard migration")
    require(ios_app, "BackendDashboardNoticeView()", "iOS school dashboard migration")
    # Camera and privacy contract.
    require(ios_info, "NSCameraUsageDescription", "iOS camera permission")
    require(ios_body, "AVCaptureDevice", "iOS in-app camera")
    require(ios_body, "AVSpeechSynthesizer", "iOS voice guidance")
    require(android_manifest, "android.permission.CAMERA", "Android camera permission")
    require(android_body, "CameraSelector", "Android in-app camera")
    require(android_body, "TextToSpeech", "Android voice guidance")
    require(ios_local_store, "voiceGuidanceEnabled", "iOS persisted voice preference")
    require(ios_parent_forms, "语音动作引导", "iOS voice preference control")
    require(android_local_store, "voiceGuidanceEnabled", "Android persisted voice preference")
    require(android_parent_forms, "语音动作引导", "Android voice preference control")
    require(android_manifest, "android:usesCleartextTraffic=\"false\"", "Android transport security")
    # Business-day records must not depend on the device timezone. A midnight
    # drift would make check-ins, body follow-ups and growth calendars disagree
    # between iOS, Android and the school dashboard.
    require(ios_business_clock, 'Asia/Shanghai', "iOS business timezone")
    require(ios_business_clock, 'static func day', "iOS business-day formatter")
    require(ios_state, 'TimeZone(identifier: "Asia/Shanghai")', "iOS session date timezone")
    require(android_business_clock, 'Asia/Shanghai', "Android business timezone")
    require(android_business_clock, 'fun day', "Android business-day formatter")
    require(android_state, 'BusinessClock.day()', "Android session date timezone")
    require(ios_body_screen, 'BusinessClock.startOfDay', "iOS body-plan date timezone")
    require(ios_parent_screen, 'BusinessClock.calendar', "iOS growth-calendar timezone")
    require(android_body_screen, 'BusinessClock.day()', "Android body date timezone")
    require(android_follow_along, 'BusinessClock.format', "Android training receipt timezone")
    # The current backend has no family exercise check-in endpoint. A remote
    # dashboard acknowledgement must not make a local-only check-in appear
    # server-synced.
    require(ios_parent_screen, '打卡记录会自动保存并同步', "iOS check-in status")
    require(android_parent_forms, '打卡记录会自动保存并同步', "Android check-in status")
    require(ios_body_screen, '计划进度已保存，联网后自动同步提醒', "iOS plan-progress status")
    require(android_body_screen, '计划进度已保存，联网后自动同步提醒', "Android plan-progress status")
    # Camera analyzers run on a best-effort, asynchronous detector stream. A
    # force unwrap here would turn a transient missing landmark or preview into
    # a production crash, so keep this invariant close to the cross-platform
    # contract instead of relying on review memory.
    if "!!" in android_body or "!!" in ios_body:
        raise AssertionError("camera analyzers must fail closed; force unwrap found")
    # The same rule applies to all Android production code. Tests may use
    # force-unwrapping for fixture parsing, but a malformed school payload or
    # missing reference row must never crash the shipped app.
    android_production = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((ROOT / "android/app/src/main/java").rglob("*.kt"))
    )
    if "!!" in android_production:
        raise AssertionError("Android production sources must not contain force unwrap (!!)")
    ios_production = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((ROOT / "ios/XiangshangYouth").rglob("*.swift"))
    )
    if "try!" in ios_production or " as!" in ios_production:
        raise AssertionError("iOS production sources must not contain try!/as! force casts")
    # Swift interpolation mistakes compile successfully but leak placeholder
    # text to reports and telemetry. Keep a small guard for the patterns that
    # have previously appeared in user-visible identifiers and copy.
    for literal in (
        '"(student.name)',
        '"(student.rawValue)',
        '"(task.rawValue)',
        '"policy-(student.grade)"',
        ' (loaded)',
        ' (total)',
    ):
        if literal in ios_production:
            raise AssertionError(f"iOS user-facing interpolation placeholder found: {literal}")
    require(android_body, "暂未看清关键点", "Android camera missing-landmark fallback")
    require(ios_body, "暂未看清关键点", "iOS camera missing-landmark fallback")

    # Mock/remote boundary and release guards.
    require(ios_repo, "MockRepository", "iOS Mock default")
    require(ios_repo, "RemoteRepository", "iOS Remote seam")
    require(android_repo, "MockRepository", "Android Mock default")
    require(android_repo, "RemoteRepository", "Android Remote seam")
    require(android_gradle, "Release build cannot use the placeholder", "Android release guard")
    require(ios_auth, "微信登录", "iOS commercial login alternatives")
    require(ios_auth, "家长注册", "iOS parent registration label")
    require(android_auth, "家长注册", "Android parent registration label")
    require(read("ios/XiangshangYouth/Features/Parent/ParentViews.swift"), "TabView(selection:", "iOS native parent tab bar")
    require(read("ios/XiangshangYouth/Features/Teacher/TeacherViews.swift"), "TabView(selection:", "iOS native teacher tab bar")
    require(read("android/app/src/main/java/com/xiangshang/youth/feature/parent/ParentScreens.kt"), "NavigationBarItem", "Android native parent tab bar")
    require(read("android/app/src/main/java/com/xiangshang/youth/feature/teacher/TeacherScreens.kt"), "NavigationBarItem", "Android native teacher tab bar")
    require(android_auth, "微信登录", "Android commercial login alternatives")
    require(ios_auth_api, "startWechatAuthorization", "iOS WeChat OAuth start seam")
    require(ios_auth_api, "exchangeWechat", "iOS WeChat OAuth exchange seam")
    require(ios_router, "wechat-callback", "iOS WeChat callback deep link")
    require(android_auth_api, "startWechatAuthorization", "Android WeChat OAuth start seam")
    require(android_auth_api, "exchangeWechat", "Android WeChat OAuth exchange seam")
    require(android_deep_link, "WechatCallback", "Android WeChat callback deep link")
    require(backend_config, "WECHAT_APP_ID", "backend WeChat configuration")
    require(backend_server, "/v1/auth/oauth/wechat/exchange", "backend WeChat exchange endpoint")

    # Large schools must not be forced through an unbounded mobile dashboard.
    # The server returns aggregate metrics plus a bounded student directory;
    # both native clients expose an explicit append-more path for the teacher
    # list and retain the total/page metadata.
    require(ios_stats_api, 'studentPage', "iOS dashboard pagination query")
    require(ios_stats_api, 'studentPageSize', "iOS dashboard page-size query")
    require(ios_remote_repo, 'studentPageSize: 100', "iOS bounded dashboard request")
    require(ios_state, 'loadMoreStudents', "iOS student directory pagination")
    require(android_stats_api, 'studentPage', "Android dashboard pagination query")
    require(android_stats_api, 'studentPageSize', "Android dashboard page-size query")
    require(android_remote_repo, 'coerceIn(1, 100)', "Android bounded dashboard request")
    require(android_state, 'loadMoreStudents', "Android student directory pagination")
    require(backend_server, 'studentTotal', "backend dashboard pagination metadata")
    require(read("backend/openapi.yaml"), 'name: studentPage', "OpenAPI dashboard pagination")

    # User-facing forms must not contain canned demo contact details or
    # prefilled appointment copy.  Mock identities remain in repositories and
    # tests, but production form fields start empty or use the authenticated
    # profile only after the user opens the form.
    for label, form in (
        ("iOS parent forms", ios_parent_forms),
        ("Android parent forms", android_parent_forms),
        ("iOS teacher forms", ios_teacher_forms),
        ("Android teacher forms", android_teacher_forms),
    ):
        for demo in ("13800138000", "2026-09-12 上午", "想了解孩子的运动发展建议。", "我想了解体质成长课程。"):
            if demo in form:
                raise AssertionError(f"{label}: demo form value must not be shipped: {demo}")
    for label, form in (("iOS teacher forms", ios_teacher_forms), ("Android teacher forms", android_teacher_forms)):
        for demo in ("完成侧向滑步与障碍跳训练，学生整体表现良好。", "课堂活动照片.jpg"):
            if demo in form:
                raise AssertionError(f"{label}: demo upload value must not be shipped: {demo}")
    for label, state_source in (("iOS app state", ios_state), ("Android app state", android_state)):
        for demo in ("已确认课后测评记录", "课堂记录.jpg"):
            if demo in state_source:
                raise AssertionError(f"{label}: legacy shortcut upload value must not be shipped: {demo}")
    require(ios_state, "attendanceCount > 0", "iOS submitted upload validation")
    require(android_state, "CourseUploadValidator.isValidForSubmission", "Android submitted upload validation")
    require(android_upload_validator, "attendance > 0", "Android upload validator positive attendance")

    # Teacher queue edits use optimistic concurrency across both native clients.
    # A stale status must be rejected by the service rather than silently
    # overwriting another teacher's update.
    require(ios_student_model, "taskVersion", "iOS task row version model")
    require(ios_task_api, "expectedVersion", "iOS task status version payload")
    require(ios_state, "acknowledgeTaskStatusVersion", "iOS task status acknowledgement")
    require(android_student_model, "taskVersion", "Android task row version model")
    require(android_task_api, "expectedVersion", "Android task status version payload")
    require(android_state, "acknowledgeTaskStatusVersion", "Android task status acknowledgement")
    require(backend_server, "VERSION_CONFLICT", "backend task version conflict")
    require(backend_server, "taskVersion", "backend dashboard task version")

    # Families must have a real withdrawal path for child health-data consent;
    # policy copy alone is not an actionable privacy control.
    require(ios_student_api, "revokeConsent", "iOS consent withdrawal API")
    require(ios_state, "revokeHealthConsent", "iOS consent withdrawal state")
    require(android_student_api, "revokeConsent", "Android consent withdrawal API")
    require(ios_account_deletion_api, "v1/me/deletion-request", "iOS account deletion API")
    require(ios_state, "submitAccountDeletionRequest", "iOS account deletion workflow")
    require(ios_parent_forms, "申请注销当前账户", "iOS account deletion entry")
    require(android_account_deletion_api, "v1/me/deletion-request", "Android account deletion API")
    require(android_state, "submitAccountDeletionRequest", "Android account deletion workflow")
    require(android_parent_forms, "申请注销当前账户", "Android account deletion entry")
    require(android_state, "revokeHealthConsent", "Android consent withdrawal state")

    # Test contract: both platforms must exercise role switching and binding,
    # not merely compile a screen.
    require(ios_ui_tests, "testParentBindingUnlocksReportAndKeepsReturnPath", "iOS binding flow test")
    require(ios_ui_tests, "testLoginMethodSwitchesExposeTheirFormControls", "iOS login method test")
    require(android_ui_tests, "loginFlowsThroughAllRolesAndParentBinding", "Android binding flow test")
    require(android_ui_tests, "校长端", "Android principal removal assertion")
    require(ios_ui_tests, "UICTContentSizeCategoryAccessibilityXXXL", "iOS large-text UI test")
    require(android_ui_tests, "launchScreenshotIsSavedForVisualEvidence", "Android screenshot evidence test")
    require(mobile_ci, "release_preflight.py", "CI release preflight")
    require(mobile_ci, "device_matrix_preflight.py", "CI device matrix evidence")
    require(read("scripts/visual_regression.py"), "maxChangedPixelRatio", "visual regression script")
    require(read("qa/visual-baseline/README.md"), "不能把当前构建截图复制成 baseline", "visual baseline policy")

    print("frontend contract OK (launch, role routing, camera, privacy, data seam, pagination, release guards, UI flows)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"frontend contract FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
