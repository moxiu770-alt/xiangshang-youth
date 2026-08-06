# 向上少年 Android

Kotlin + Jetpack Compose + MVVM + StateFlow 的一期原生客户端。默认使用 `MockRepository`，网络层通过 Retrofit/OkHttp 的 `ApiClient` 和各 API 类型预留，切换到 `RemoteRepository` 不需要修改页面。

联调时可用 `-PapiBaseUrl=https://staging.example.com/` 注入 Retrofit 地址；请求统一附带 KeyStore 中的 Bearer token，并将超时、取消、401/403、5xx 和网络异常映射到 `ApiError`。不传该参数时仍使用示例地址，Mock 模式不会发起网络请求。

## 启动

```bash
cd android
./run-android-checks.sh
```

生成的 APK 位于 `app/build/outputs/apk/debug/app-debug.apk`。使用 Android Studio 打开 `android` 目录即可运行模拟器或真机。

`run-android-checks.sh` 会自动使用 Android Studio 内置 JDK，并设置本机 Android SDK；它会同时执行 Debug APK 构建、`testDebugUnitTest` 和 `lintDebug`。如果只需要构建：

```bash
cd android
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="/Users/luyanpeng/Library/Android/sdk"
./gradlew :app:assembleDebug
```

本机已配置 `XiangshangYouth_QA_API34` 和 `ChangXiang_A34` 两个模拟器，项目 SDK 路径写在 `local.properties` 中。

默认测试登录页使用预填账号，登录后可以选择家长、教师或校长角色。

发布校验：`./gradlew :app:assembleRelease` 已可构建，产物为 `app/build/outputs/apk/release/app-release-unsigned.apk`；真实上架前需要配置发行签名与 Play/App Store 审核材料。
