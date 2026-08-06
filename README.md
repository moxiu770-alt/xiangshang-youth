# 向上少年综合运动能力 AI 诊断平台

原生双端一期前端工程：

- `ios/XiangshangYouth`：SwiftUI + MVVM + Combine/ObservableObject
- `android`：Kotlin + Jetpack Compose + ViewModel + StateFlow

两端默认使用一致的 `MockRepository`，页面不依赖后端即可启动。网络层已通过 `ApiClient`、Auth/Student/Task/Report/Message/Stats API 和 `RemoteRepository` 预留；后端联调时只需切换数据源，不修改页面路由和组件。

## 本地验证

### iOS

```bash
xcodebuild test \
  -project ios/XiangshangYouth/XiangshangYouth.xcodeproj \
  -scheme XiangshangYouth \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

### Android

```bash
cd android
./run-android-checks.sh
```

脚本会构建 Debug APK、运行 JVM 单元测试并执行 `lintDebug`。APK 输出在 `android/app/build/outputs/apk/debug/app-debug.apk`；Compose 仪器测试需要连接真机或可用模拟器：

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="/Users/luyanpeng/Library/Android/sdk"
./gradlew :app:assembleAndroidTest
```

如果 AVD 启动后出现 Android 系统自身的 “System UI isn't responding”，先重启或更换 AVD；该弹窗来自模拟器系统进程，不代表 APK 构建失败。`assembleDebug`、`testDebugUnitTest` 和 `lintDebug` 可在没有可用设备时完成静态验收。

发布构建可用 `./gradlew :app:assembleRelease` 验证；当前输出为 `app-release-unsigned.apk`，需接入学校/发行方签名证书后才能上架。

## 运行入口

启动后进入启动海报和登录页。登录后可选择家庭端、学校教师端或校长端；Mock 数据包含 1 所学校、3 个年级、6 个班级、20 名学生、2 个家庭绑定候选、3 个任务、7 项体测和报告/消息/课程建议。

## 当前工程约定

- Token 使用 iOS Keychain / Android Keystore；本地草稿、绑定关系和测评交互状态默认使用 iOS Keychain / Android Keystore 加密保存。Android Keystore 暂时不可用时会降级，不阻塞 Mock 启动。
- 本地草稿、绑定关系、测评状态、班级动态和课程进度会保存，登录失败、恢复失败、空数据和重试状态均由页面处理；双端根工作台支持主动刷新，Android 提供刷新按钮与全局错误重试，iOS 支持系统下拉刷新；登录页可打开协议/隐私说明。
- 深链格式：`xiangshang-youth://open?target=report&studentId=s01`，支持报告、复核、任务和风险入口。
- Android 页面和关键卡片已补充 TalkBack 语义；iOS 使用 VoiceOver accessibility label。
- 启动海报已统一为清理系统状态栏和底部 Home 指示条后的清晰视觉资源：iOS 1x/2x/3x 与 Android `drawable-nodpi` 使用同一画面比例；iOS 包含 `PrivacyInfo.xcprivacy`，Android 禁止明文流量和自动备份。

## 前端落地差距（不含后端）

当前工程已经覆盖一期主要角色、路由、Mock 数据和核心操作；下面是从“视觉/交互内测”到“可交付学校试点”仍需完成的前端工作。后端接口接入不计入以下完成度。

### P0：试点前必须补齐

- **逐页状态机**：每个列表、详情、提交、上传和刷新入口都要统一覆盖 `idle / loading / success / empty / error / retry`，并补充防重复提交、超时和取消行为。当前 Mock 主流程、教师通知、校长统计次级页已补齐主要状态，仍需逐页接入统一状态容器。
- **真实交互反馈**：报名、复核、补测、动态、课程上传、客服咨询、设置和忘记密码已具备 Mock 校验、成功反馈与本地持久化；联调前要把本地写入抽象为可替换 command/use-case，并补充失败回滚与超时模拟。
- **登录与账号恢复**：微信/手机号/账号登录的回调、验证码失效、切换账号、注销、会话过期和深链冷启动需要在真实设备上走通；当前页面和本地会话已具备，第三方 SDK 回调待接入。
- **权限与系统能力**：通知权限已接入 iOS `UNUserNotificationCenter` 与 Android 13+ `POST_NOTIFICATIONS`，并覆盖拒绝后的可恢复提示；照片/文件选择、相机、分享、系统浏览器和外部登录回跳仍需在真实业务接入时统一权限解释、拒绝后的降级 UI。

### P1：达到商业交付质量

- **响应式与字体**：按小屏 Android、iPhone SE、全面屏、横屏和平板建立断点；移除关键页面的固定宽高假设，验证系统大字号、粗体、动态字体后不截断、不重叠。
- **无障碍验收**：逐页补齐 VoiceOver/TalkBack 标签、语义分组、焦点顺序、按钮状态和颜色对比度；当前关键卡片已接入，仍需真实辅助功能走查。
- **视觉回归**：以 13 张参考图建立 iOS/Android 同尺寸基线截图，覆盖启动页、三角色首页、报告、任务、班级/年级/校长看板；每次改动做像素差异和人工复核。
- **导航一致性**：一级工作台不显示返回，二级页可返回，弹窗/Sheet/深链关闭后恢复原上下文；需要补充 Android 系统返回键、iOS 手势返回和重复跳转的回归用例。
- **离线与恢复**：网络断开、切后台、进程重建、旋转和低内存后，草稿、绑定孩子、已读状态、测评进度和提交状态要可恢复，并明确“本地已保存/待同步”提示。当前关键本地状态已持久化，仍需真机低内存和系统杀进程验收。
- **错误与空态文案**：根工作台已提供可执行的刷新/重试入口，不能只显示“暂无数据”；剩余二级列表仍需逐页确认错误文案、重试触发和筛选条件保留。

### P2：规模化运行前

- **质量工程**：补齐 iOS XCTest/SwiftUI UI Test、Android JVM/Compose UI Test、关键路径覆盖率、lint/format、依赖和资源检查、视觉快照回归。
- **发布配置**：生产 Bundle/Application ID、通知权限说明、文件/相机权限文案、Universal Link、签名、Release 构建和崩溃兜底页；隐私清单、通知权限代码、应用 Scheme 和 Android 明文流量/备份策略已落地，真实渠道与签名仍需在联调发布阶段替换。
- **性能与资源**：图片缓存/失败兜底、列表分页或窗口化、骨架屏、动画减弱模式、启动耗时和大数据量看板性能基线。
- **可观测性**：前端错误日志、页面/按钮埋点、关键流程漏斗、版本和环境开关；不记录手机号、学生健康数据等敏感明文。
- **产品化细节**：统一日期/数字/状态颜色规范、隐私与用户协议版本、账号注销入口、数据导出/删除提示、客服与反馈闭环、必要的中英文/无障碍文案。

### 当前结论

在不计后端的前提下，当前可视为“可演示的一期前端 + Mock 闭环”：视觉/交互内测约 **75%–80%**，一期业务闭环前端约 **65%–70%**，学校试点交付约 **55%–65%**，规模化商业前端约 **40%–50%**。剩余差距主要集中在真实第三方登录/权限渠道、设备矩阵和视觉快照回归、Release 签名与商店审核材料、真实崩溃/埋点服务，以及 Android 真机仪器测试；这些不应被 Mock 或单元测试结果替代。

## Git

当前本地分支为 `main`。提交前运行 `git diff --check`、iOS 测试和 `android/run-android-checks.sh`。仓库尚未配置远程地址，接入 GitHub/GitLab 后再执行：

```bash
git remote add origin <仓库地址>
git push -u origin main
```
