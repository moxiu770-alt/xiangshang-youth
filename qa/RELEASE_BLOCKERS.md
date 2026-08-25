# 发布门禁与外部依赖

本轮已完成的代码级门禁：

- 后端 `npm run check` 与 59 项单元/契约测试通过；OpenAPI 文件已通过 Redocly lint。集成测试仍需独立 `TEST_DATABASE_URL`，不能连接开发库代替。
- 服务端写入字段已启用严格 JSON 标量校验：文本、手机号、密码拒绝对象/数组强制转字符串，活动、预约、课程、班级动态和客服工作流继续执行长度、权限和幂等校验。
- 模型跨端契约 225 项不变量通过；84 条黄金样本通过；39,572 个边界 fuzz 用例通过；校准候选生成通过。
- iOS Swift 源码解析通过；iPhone 17 Pro / iOS 26.5 模拟器已执行 89 个 XCTest（0 失败）和 6 个 UI 测试（0 失败）；覆盖辅助功能超大字号登录、角色切换、教师下钻、家庭绑定、报告返回栈和纯启动海报，xcresult 保留关键页面截图附件；真机矩阵仍待验收。
- iOS App、XCTest 和 UI test target 已统一 Development Team；真机安装所需的 Runner provisioning profile 仍由 Apple Developer 账号生成。
- Android 的远程会话刷新、403 权限错误边界、Keystore 不可用时的内存降级已接入；本机已完成 Debug 单元测试 94 项（0 失败）并生成 Debug/Release APK。新增任务版本、语音偏好和业务时钟边界回归测试已纳入该数量。
- Android Compose instrumentation test APK 已成功编译，新增启动海报截图写入测试沙盒并由 CI 拉取上传；本机 Android SDK 的 `adb` 可用但没有连接设备，仍未宣称真机/AVD 流程通过。
- Android `lintDebug` 已通过，主 CI 现在同时编译 JVM、Debug APK、instrumentation APK 并上传测试 APK artifact；本轮又完成了实时姿态关键点缺失帧的失败闭合保护，并复跑 Debug 单测与 lint。
- 双端生产源码已移除强制解包路径：Android 不再使用 `!!`/`requireNotNull`/`checkNotNull`，iOS 不再使用 `try!`/`as!`；报告冲突计算、身高参考表、附件 URI、请求 URL 和本地账号名称在异常输入下均失败闭合或使用明确兜底，不把坏数据升级为崩溃。
- Android Release（`useRemoteDataSource=true`、生产 API 占位地址、R8/minify）构建与 `lintRelease` 已通过；iOS Release Simulator 构建也已通过。两端远程模式继续保持“无权限不切角色、报告仅限已绑定孩子”的深链边界。
- 主 CI 已加入干净 API 35 Pixel 2 模拟器的 Compose instrumentation 流程；本机没有连接 Android 设备，本地结果不替代该 CI 运行记录。
- 双端身体测评完成记录现在带有独立的远程确认状态；提交失败会进入本机待同步队列，可从“我的/设置 → 立即同步”重试。
- 双端远程学生目录已接入有界分页：首屏最多 100 条，服务端返回总量/页码，教师学生列表可继续加载，不再无界拉取全校名单。
- 双端家长报名/专家预约表单已移除演示手机号、日期和咨询文案；打开表单时仅从当前账号带入有效手机号，空值由真实输入、校验和草稿流程承接。
- 双端教师延时课程上传表单已移除预填出勤人数、课堂记录和附件名；新建记录从空表单开始，仅恢复已保存的本机草稿/记录，并由前端契约门禁防止演示字段回归。
- 教师课程提交的底层状态机也已收紧：正式进入同步队列必须有正出勤人数、非空课堂记录、附件名和文件引用；旧的仅传 task ID 快捷入口已改为显式表单参数，不能伪造成功上传。
- 教师测评状态更新已接入双端乐观并发控制：客户端携带 `expectedVersion`，服务端按任务行版本原子更新并返回新版本；冲突会清除本地陈旧状态，避免两个教师终端互相覆盖或无限重试。
- 移动端校长工作台旧页面源码已移除；校长账号仅保留后台看板入口提示，避免死路由和重复维护。
- Windows 场地端请求签名已绑定请求体 SHA-256；本机 `.NET 8` 核心测试 7 项通过，Windows CI 仍负责 WPF 发布产物验收。
- 发布预检已脚本化：`release_preflight.py` 的 local 模式和设备矩阵预检已接入主 CI；pilot/production 通过手工 workflow 注入真实 secret 后执行严格门禁，预检 JSON 作为发布证据上传。
- 本轮又修复了两个导航/会话安全边界：iOS 风险通知进入学校后台看板时重置为角色根页（不再产生多余返回键），深链在角色切换回调前消费以避免重复入栈，切换账号和 401 会话失效同时清理 access/refresh token；Android 远端模型版本不兼容统一映射为可读的模型契约错误。Android Debug 单测、Debug Lint、带非占位 HTTPS 配置的 Release + `lintRelease`、instrumentation APK 已复跑通过；iOS `build-for-testing` 已复跑通过，模拟器服务当前不可用，未将本轮 XCTest 运行冒充为通过。
- Android 身体测评的四项拍摄入口、28 天跟练日卡和动作选择卡已补齐 TalkBack 按钮语义及动态状态文案；Debug 单测、Lint 和 instrumentation APK 再次通过。真实 TalkBack 焦点顺序和摄像头操作仍需设备走查。
- 双端涉及签到、家庭观察、姿态/BMI 复测、跟练回执和成长月历的业务日期统一使用 `Asia/Shanghai`；Android `BusinessClock` 边界单测覆盖 UTC 午夜附近场景，Android 单测/Lint/instrumentation APK 已复跑通过；iOS 源码解析通过，测试目标此前成功 `build-for-testing`，本轮复跑受 CoreSimulator/构建服务卡住影响未完成。
- 已修正同步真实性边界：家长运动打卡已增加结构化服务端 `health-checkins` 接口（孩子与业务日期唯一、版本冲突、幂等提交、失败重试），双端表单和本地待同步队列已接通；视力、口腔和心理观察已升级为稳定 questionId 与 single/multiple/frequency/severity/text 结构，服务端拒绝非法答案类型；28 天跟练进度继续使用结构化 `training-sessions` 回执。仍需在独立测试数据库验证迁移、跨设备冲突和学校时区边界。
- 本轮继续清理真实 UI 缺陷：教师 iOS 三个工作台入口统一恢复可点击消息铃铛；报告待发布文案、学生目录分页计数和姿态快照 ID 不再显示 Swift 插值占位符；跨端契约新增占位符回归拦截。
- 家长首页的“推荐训练/运动安排”入口已在 iOS 与 Android 统一改为可点击课程入口，并移除没有真实预约依据的“已预约”状态；活动日期改为“2026 秋季测评 · 以学校通知为准”，避免过期 Mock 日期继续出现在正式界面。
- 家长“数据与隐私”已补齐身体测评数据使用同意的撤回入口：双端均有二次确认、提交中/成功/失败状态，并通过服务端既有 consent 接口写入撤回记录；撤回不会伪造删除已完成学校记录。
- 家长“数据与隐私”已补齐账户注销入口：双端均有二次确认、提交中/成功/失败状态；服务端提供用户申请、管理员审核、异步匿名化、会话撤销、直接身份/用户内容清理和审计链，学校留存记录按留存规则处理。
- 本轮视觉修正已完成：教师登录入口改为“家长注册”并保留学校后台批量授权边界；iOS 家长/教师工作台改用系统原生毛玻璃 TabView，Android 使用 Material NavigationBar；导航字号、登录协议/错误提示和主要卡片层级已放大，技术化“待学校服务确认”文案改为更简洁的同步状态。
- 本轮继续收口视觉残留：双端页面最小字号统一提升至可读范围，报告状态统一为“等待报告/报告更新中”，活动、评论、课程、预约和设置页不再展示“本机/学校服务接入”等技术实现词；登录卡片在小屏与键盘场景下缩短固定占比，保留滚动可达性。

以下事项不是代码可以凭空完成的发布前置条件，必须由项目环境或业务方补齐：

1. 配置生产密钥：`VERIFICATION_CODE_PEPPER`、`MFA_ENCRYPTION_KEY`、`AUDIT_LOG_SIGNING_KEY`、`FIELD_DEVICE_SIGNING_ENCRYPTION_KEY`、对象存储凭证和指标令牌。
2. 接入真实短信、微信开放平台和推送服务商，并完成回调域名、AppID/Secret、隐私条款和应用商店审核材料。微信 OAuth 的服务端 state、防重放、身份表、回调中转和双端 API/深链代码已落地，但没有真实凭据时不会伪造登录成功。
3. iOS 工程已接入 Sentry Cocoa Swift Package 和 `CrashMonitoring` 封装；仍需在可联网 CI/发布机完成依赖解析、配置生产 DSN，并验证真实崩溃上报与告警接收。
4. 使用经过授权的人类标注集完成姿态、动作跟练和体测模型校准；当前黄金集明确标记为 `pending-human-validation`，不能作为医学或学校正式评分依据。
5. 完成 iOS/Android 真机矩阵（小屏、平板、横屏、系统字体放大、相机权限、前后台切换）并保存 XCTest/Compose UI、崩溃和性能报告；XCTest/UI target 已补齐 Development Team，但当前 iPhone 真机仍缺少 `com.xiangshang.youth.uitests.xctrunner` 对应的开发 provisioning profile，需要在已登录 Apple Developer 账号的发布机执行签名配置。
6. 为正式环境配置 Git 远程仓库、分支保护、签名证书、灰度发布、回滚版本和实际告警接收人；本地仓库不擅自推送或伪造这些外部配置。

本次本机验证记录（2026-08-25）：跨端前端契约门禁通过；local 发布预检通过并生成 JSON；设备矩阵预检如实记录 `xcrun` 与 Android SDK 内的 `adb` 可用、但没有连接设备；Android Debug 单测、Lint、Debug/Release APK 与 instrumentation APK 构建通过；iOS 使用可用的 iPhone 17 / iOS 26.5 模拟器执行 89 个 XCTest、6 个 SwiftUI UI 测试均 0 失败；后端 `npm run check`、Redocly OpenAPI lint 与 59 项单元/契约测试通过；班级圈评论删除权限投影、跟练结构化回执、家庭运动打卡远程契约和健康观察结构化答案在本轮重新验证。Android 真机/AVD 仍因无连接设备未执行；后端集成测试仍因未提供 `TEST_DATABASE_URL` 未执行；iOS 真机测试仍需正式 provisioning profile；场地端 `.NET 8` 核心测试不在本轮重跑范围。剩余未验证项必须在配置签名、真机、联网 CI 和独立测试数据库环境重跑发布命令，详见 [RELEASE_PREFLIGHT.md](RELEASE_PREFLIGHT.md)。

补充记录（2026-08-25）：已启动 `XiangshangYouth_QA_API34` Android 模拟器并执行 `:app:connectedDebugAndroidTest`，4/4 通过。覆盖纯启动图、启动截图、公开登录只能进入家庭端并完成绑定/报告/课程路径，以及安全本地存储往返。该结果是模拟器验收，不替代真实 Android 设备矩阵。

验收命令：

```bash
cd backend && npm run check && npm test && npm run lint:openapi
cd ../android && ./gradlew :app:testDebugUnitTest :app:assembleRelease --no-daemon
xcodebuild -project ../ios/XiangshangYouth/XiangshangYouth.xcodeproj -scheme XiangshangYouth test
cd ../field-client && dotnet test FieldClient.Core.Tests/FieldClient.Core.Tests.csproj --configuration Release
```
