# 向上少年综合运动能力 AI 诊断平台

原生双端一期前端工程：

- `ios/XiangshangYouth`：SwiftUI + MVVM + Combine/ObservableObject
- `android`：Kotlin + Jetpack Compose + ViewModel + StateFlow
- `field-client`：Windows 11 WPF 场地体测端 + SQLite 离线队列 + 中央服务补传

后端与数据库首版已放在 `backend`：Node.js API、PostgreSQL schema/seed、登录会话、学校/学生、测评任务、报告、消息、审计日志和管理后台。启动方式见 [`backend/README.md`](backend/README.md)。

电脑体测端与 App、后台共用中央业务数据，但使用独立设备凭证与离线同步协议。构建、环境变量和 Windows 部署说明见 [`field-client/README.md`](field-client/README.md)。

两端默认使用一致的 `MockRepository`，页面不依赖后端即可启动。网络层已通过 `ApiClient`、Auth/Student/Task/Report/Message/Stats API、`WorkflowApi` 和 `RemoteRepository` 预留；报名、专家预约、课程上传、复核/补测、班级动态、客服咨询等写操作统一经过 command/use-case 状态边界，后端联调时只需切换数据源，不修改页面路由和组件。

## 本地验证

### iOS

```bash
xcodebuild test \
  -project ios/XiangshangYouth/XiangshangYouth.xcodeproj \
  -scheme XiangshangYouth \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

该 scheme 已包含 `XiangshangYouthUITests`：会从启动海报等待登录页，完成协议确认、Mock 微信登录、教师端与家庭端进入/退出；学校管理数据看板由后台系统提供，不再进入移动端校长工作台。如只需运行这条冒烟链路，可追加 `-only-testing:XiangshangYouthUITests/LaunchAndRoleFlowTests`。

Release 编译校验（不签名的模拟器产物）可使用：

```bash
xcodebuild build \
  -project ios/XiangshangYouth/XiangshangYouth.xcodeproj \
  -scheme XiangshangYouth \
  -configuration Release \
  -sdk iphonesimulator \
  API_BASE_URL=https://staging.example.edu.cn/ \
  USE_REMOTE_DATA_SOURCE=1 \
  CODE_SIGNING_ALLOWED=NO
```

该命令验证 Release 编译与资源打包；Release 会拒绝占位中央服务地址或 Mock 数据源。真机 TestFlight / App Store 发布仍需由发行团队配置 Apple 开发者签名、Provisioning Profile、真实 HTTPS 服务地址和 Archive 导出。

### Android

```bash
cd android
./run-android-checks.sh
```

脚本会构建 Debug APK、AndroidTest APK、运行 JVM 单元测试并执行 `lintDebug`；如果检测到 Android 真机/模拟器，还会自动执行 Compose 仪器测试。APK 输出在 `android/app/build/outputs/apk/debug/app-debug.apk`；

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="/Users/luyanpeng/Library/Android/sdk"
./gradlew :app:assembleAndroidTest
```

如果 AVD 启动后出现 Android 系统自身的 “System UI isn't responding”，先重启或更换 AVD；该弹窗来自模拟器系统进程，不代表 APK 构建失败。`assembleDebug`、`testDebugUnitTest` 和 `lintDebug` 可在没有可用设备时完成静态验收。

发布构建必须显式传入真实 HTTPS 中央服务并启用远程数据源：`./gradlew :app:assembleRelease -PapiBaseUrl=https://<正式或预发布中央服务>/ -PuseRemoteDataSource=true`。Release 会拒绝 `http://`、占位地址及 Mock 数据源；当前输出为 `app-release-unsigned.apk`，需接入学校/发行方签名证书后才能上架。

### Windows 场地体测端

```bash
export DOTNET_ROOT="$(pwd)/.tooling/dotnet"
"$DOTNET_ROOT/dotnet" restore field-client/FieldClient.Core.Tests/FieldClient.Core.Tests.csproj --locked-mode
"$DOTNET_ROOT/dotnet" test field-client/FieldClient.Core.Tests/FieldClient.Core.Tests.csproj --configuration Release --no-restore
"$DOTNET_ROOT/dotnet" build field-client/FieldClient.Windows/FieldClient.Windows.csproj --configuration Release --no-restore
```

Windows 实机须由部署工具提供设备凭证和 HTTPS 中央服务地址；首次运行前先在后台“场地中控”注册测试点与边缘主机。具体环境变量和硬件适配要求见场地端说明。

## 运行入口

启动后进入启动海报和登录页。移动端登录后可选择家庭端或学校教师端；校长/学校管理数据统一在后台数据看板查看。Mock 数据包含 1 所学校、3 个年级、6 个班级、20 名学生、2 个家庭绑定候选、3 个任务、7 项体测和报告/消息/课程建议。Mock 家长绑定示例为：王小明 + `XS-S01`、王小雨 + `XS-S02`；正式环境以学校后台发放的绑定码为准。

## 当前工程约定

- Token 使用 iOS Keychain / Android Keystore；本地草稿、绑定关系和测评交互状态默认使用 iOS Keychain / Android Keystore 加密保存。Android Keystore 暂时不可用时会降级，不阻塞 Mock 启动。
- 本地草稿（含活动报名、预约、课程上传、班级动态、帮助与反馈）、绑定关系、测评状态、班级动态和课程进度会保存，测评步骤/答案支持配置变更后的恢复；登录失败、恢复失败、空数据和重试状态均由页面处理；本地提交使用独立的 `pendingSync` 状态，兼容旧版本 `submitted` 数据，避免把 Mock 写入误当成学校服务已确认；双端根工作台支持主动刷新，Android 提供刷新按钮与全局错误重试，iOS 支持系统下拉刷新；登录页可打开协议/隐私说明。双端会监听网络状态，在断网时显示“离线模式”提示，明确当前内容可能是本地 Mock/缓存数据。
- 深链格式：`xiangshang-youth://open?target=report&studentId=s01`，支持报告、复核、任务和风险入口。
- 报告详情页保留本地可读报告，进入页面或点击“同步报告”会走独立的异步报告数据源；请求期间只锁定报告同步按钮，失败显示页内重试/关闭，不覆盖其他工作台的刷新状态；切换账号或退出登录时会丢弃未完成请求的旧会话响应。
- 报名、专家预约、课程上传、教师状态更新、班级动态和客服咨询均使用独立的 workflow command 状态（`idle / submitting / succeeded / failed`），页面统一显示提交中、成功、失败和重试；教师状态更新额外携带任务行 `expectedVersion`，服务端返回新版本并持久化，发生并发冲突时清除本地陈旧投影并提示刷新；Mock 实现不发网络请求，Remote 实现调用版本化 endpoint，后端联调不需要重写页面状态。
- 家长可在“我的 → 数据与隐私”中申请导出/删除孩子数据、撤回身体测评数据使用同意或申请注销当前账户；三类动作都有二次确认和独立 workflow 状态。账户注销由平台审核后异步撤销会话、清理直接身份和用户内容并保留必要审计；已完成的学校记录不会被客户端伪造为立即删除。
- 家长运动打卡与 28 天跟练进度当前是端侧成长记录，页面明确显示“本机已保存”；它们不会因为登录了 RemoteRepository 就伪装成学校服务已同步，待后端提供对应同步接口后再接入独立的 pending/success 状态。
- Android 页面和关键卡片已补充 TalkBack 语义；iOS 使用 VoiceOver accessibility label。
- 启动海报已统一为清理系统状态栏和底部 Home 指示条后的清晰视觉资源：iOS 1x/2x/3x 与 Android `drawable-nodpi` 使用同一画面比例；iOS 包含 `PrivacyInfo.xcprivacy`，Android 禁止明文流量和自动备份。
- 教师账号不在移动端自助注册：登录页仅保留“家长注册”，教师账号由学校/平台后台批量创建并授予班级权限；iOS 工作台使用系统原生毛玻璃 `TabView`，Android 使用 Material `NavigationBar`，避免自绘底栏与系统手势冲突。

## 前端落地差距（不含后端）

当前工程已经覆盖一期主要角色、路由、Mock 数据和核心操作；下面是从“视觉/交互内测”到“可交付学校试点”仍需完成的前端工作。后端接口接入不计入以下完成度。

### P0：试点前必须补齐

- **逐页状态机**：每个列表、详情、提交、上传和刷新入口都要统一覆盖 `idle / loading / success / empty / error / retry`，并补充防重复提交、超时和取消行为。当前 Mock 主流程、教师/家长主要列表与详情、通知/班级圈/课程上传已补齐页面级加载、空、错误和重试；学校总览、年级/班级/风险统计由后台看板负责，移动端仅保留跳转提示。
- **真实交互反馈**：报名、复核、补测、动态、课程上传和客服咨询已具备 Mock 校验、成功反馈、本地持久化及统一 command/use-case 状态；家长与教师表单均从空值开始，仅恢复明确保存的草稿/记录，避免把演示内容误提交；注册、短信验证码和忘记密码已接入版本化账户接口，真实联调前仍需接入短信服务商并用服务端错误码补齐失败回滚、超时和取消模拟。
- **登录与账号恢复**：手机号/账号登录、会话过期和深链冷启动已具备；微信授权已补齐服务端短时 state、防重放、身份表、HTTPS 回调中转、iOS/Android exchange API 与自定义 scheme。上线前仍需填入真实微信 AppID/Secret、配置备案回调域名并在真实设备走通 SDK/微信客户端授权。
- **网络接入边界**：iOS `URLSession` 与 Android `Retrofit/OkHttp` 已具备统一超时、鉴权、取消、401/403/5xx/网络错误映射和版本化 endpoint；默认仍为 Mock。联调时必须显式同时打开数据源和服务地址：iOS Scheme 设置 `XS_USE_REMOTE_DATA_SOURCE=1`、`XS_API_BASE_URL=https://.../`、`XS_SCHOOL_ID=<学校ID>`；Android 构建传入 `-PuseRemoteDataSource=true -PapiBaseUrl=https://.../ -PschoolId=<学校ID>`，不改页面层。
- **权限与系统能力**：通知权限已接入 iOS `UNUserNotificationCenter` 与 Android 13+ `POST_NOTIFICATIONS`，并覆盖拒绝后的可恢复提示；照片/文件选择、相机、分享、系统浏览器和外部登录回跳仍需在真实业务接入时统一权限解释、拒绝后的降级 UI。

### P1：达到商业交付质量

- **响应式与字体**：按小屏 Android、iPhone SE、全面屏、横屏和平板建立断点；移除关键页面的固定宽高假设，验证系统大字号、粗体、动态字体后不截断、不重叠。
- **无障碍验收**：逐页补齐 VoiceOver/TalkBack 标签、语义分组、焦点顺序、按钮状态和颜色对比度；当前关键卡片已接入，仍需真实辅助功能走查。
- **视觉回归**：以 13 张参考图建立 iOS/Android 同尺寸基线截图，覆盖启动页、家庭/教师首页、报告、任务和后台数据看板；每次改动做像素差异和人工复核。
- **导航一致性**：一级工作台不显示返回，二级页可返回，弹窗/Sheet/深链关闭后恢复原上下文；Android/iOS 已将登录、角色切换、退出和深链入口改为“替换根路由”，学校管理风险深链也会重置为后台看板根页，避免出现多余返回键或系统返回落回前一角色工作台；仍需补充 Android 系统返回键、iOS 手势返回和重复跳转的真机回归用例。
- **离线与恢复**：网络断开、切后台、进程重建、旋转和低内存后，草稿、绑定孩子、已读状态、测评进度和提交状态要可恢复，并明确“本地已保存/待同步”提示。当前关键本地状态已持久化，仍需真机低内存和系统杀进程验收。
- **错误与空态文案**：根工作台和主要二级页已提供可执行的刷新/重试/关闭入口，报告首次加载失败时仍保留返回导航；真实接口联调前仍需逐页确认错误文案、重试触发、筛选条件保留和服务端错误码映射。

### P2：规模化运行前

- **质量工程**：iOS XCTest 与 SwiftUI UI 冒烟链路已接入，并已在 iPhone 17 Pro 与 iPad A16 模拟器分别通过；Android JVM/Compose UI Test、关键路径覆盖率、lint/format、依赖和资源检查已接入。本机当前未连接 Android 真机/模拟器，因此仍需执行 Compose 仪器链路，视觉快照回归仍需继续补齐。
- **跨端契约门禁**：`scripts/check_frontend_contract.py` 已接入主 CI，持续检查纯启动海报、学校后台看板迁移、移动端校长工作台移除、相机/语音能力、Mock/Remote 边界、Release 地址保护和登录/绑定 UI 流程，防止后续视觉重构回归关键产品边界。
- **发布预检与设备证据**：`scripts/release_preflight.py` 区分 local/pilot/production，校验远程 HTTPS、灰度、崩溃 DSN、生产密钥、对象存储、备份和模型状态；`scripts/device_matrix_preflight.py` 只记录真实可发现的工具/设备，不把模拟器或 APK 构建冒充真机通过。主 CI 会上传预检 JSON，正式发布通过手工触发 `release-preflight.yml` 注入 secret manager 配置。
- **视觉回归**：`scripts/visual_regression.py` 只接受产品批准的同尺寸 baseline，缺图、尺寸变化或像素差异超阈值直接失败；当前 UI 测试已保留 xcresult 截图，但在 13 张参考图归档前不会伪造视觉回归通过。
- **发布配置**：生产 Bundle/Application ID、通知权限说明、文件/相机权限文案、Universal Link、签名、Release 构建和崩溃兜底页；隐私清单、通知权限代码、应用 Scheme、iOS 横竖屏声明和 Android 明文流量/备份策略已落地，iOS/Android Release 未签名构建已通过，真实渠道与签名仍需在联调发布阶段替换。
- **性能与资源**：图片缓存/失败兜底、列表分页或窗口化、骨架屏、动画减弱模式、启动耗时和大数据量看板性能基线。
- **可观测性**：前端错误日志、页面/按钮埋点、关键流程漏斗、版本和环境开关；不记录手机号、学生健康数据等敏感明文。
- **产品化细节**：统一日期/数字/状态颜色规范、隐私与用户协议版本、注销审核结果通知、数据导出/删除提示、客服与反馈闭环、必要的中英文/无障碍文案。

### 当前结论

在不计后端的前提下，当前可视为“可演示的一期前端 + Mock 闭环”：视觉/交互内测约 **75%–80%**，一期业务闭环前端约 **65%–70%**，学校试点交付约 **55%–65%**，规模化商业前端约 **40%–50%**。剩余差距主要集中在真实第三方登录/权限渠道、实体设备与平板/横屏矩阵、视觉快照回归、Release 签名与商店审核材料、真实崩溃/埋点服务；Android 仪器测试需要在连接 AVD/真机后补跑，不能用 Mock、JVM 单测或 APK 构建替代。

## Git

当前本地分支为 `main`。提交前运行 `git diff --check`、iOS 测试和 `android/run-android-checks.sh`。仓库尚未配置远程地址，接入 GitHub/GitLab 后再执行：

```bash
git remote add origin <仓库地址>
git push -u origin main
```
