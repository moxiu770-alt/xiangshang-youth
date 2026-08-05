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
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

### Android

```bash
cd android
./run-android-checks.sh
```

脚本会构建 Debug APK 并运行 JVM 单元测试。APK 输出在 `android/app/build/outputs/apk/debug/app-debug.apk`；Compose 仪器测试需要连接真机或可用模拟器：

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="/Users/luyanpeng/Library/Android/sdk"
./gradlew :app:assembleAndroidTest
```

## 运行入口

启动后进入启动海报和登录页。登录后可选择家庭端、学校教师端或校长端；Mock 数据包含 1 所学校、3 个年级、6 个班级、20 名学生、2 个家庭绑定候选、3 个任务、7 项体测和报告/消息/课程建议。

## 当前工程约定

- Token 使用 iOS Keychain / Android Keystore；Android Keystore 暂时不可用时会降级，不阻塞 Mock 启动。
- 本地草稿、绑定关系、测评状态、班级动态和课程进度会保存，登录失败、恢复失败、空数据和重试状态均由页面处理。
- 深链格式：`xiangshang-youth://open?target=report&studentId=s01`，支持报告、复核、任务和风险入口。
- Android 页面和关键卡片已补充 TalkBack 语义；iOS 使用 VoiceOver accessibility label。

## Git

当前本地分支为 `main`。提交前运行 `git diff --check`、iOS 测试和 `android/run-android-checks.sh`。仓库尚未配置远程地址，接入 GitHub/GitLab 后再执行：

```bash
git remote add origin <仓库地址>
git push -u origin main
```
